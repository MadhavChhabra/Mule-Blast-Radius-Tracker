package com.apiguard.core.mule;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import javax.xml.parsers.DocumentBuilder;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

/**
 * Auto-discovers a Mule application's dependency picture from its project files — no manifest needed.
 *
 * <p>It reads two sources of truth every Mule project already has:
 * <ul>
 *   <li><b>{@code pom.xml}</b> — Exchange API assets appear as Maven dependencies (classifier
 *       {@code raml}/{@code oas}/{@code http-api}…). These are the aggregate downstream APIs.</li>
 *   <li><b>flow XML</b> — {@code <http:request method=… path=… config-ref=…>} inside an APIkit
 *       endpoint flow (named like {@code get:\orders\(orderId):api-config}) tells you which
 *       downstream endpoint each of the app's own endpoints calls — the per-endpoint view.</li>
 * </ul>
 */
public final class MuleProjectScanner {

    private static final Set<String> HTTP_VERBS =
            Set.of("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS");

    // Connector namespace prefix -> the canonical end-system (system of record) it talks to. A Mule
    // app reaches these through a connector, not an HTTP API, but they are real downstream producers
    // (a DB, a SaaS system, a queue, a file system) and belong on the estate map. Whitelisted so we
    // never mistake a flow-control or transform element for a backend call.
    private static final Map<String, String> BACKEND_CONNECTORS = Map.ofEntries(
            Map.entry("db", "Database"),
            Map.entry("salesforce", "Salesforce"),
            Map.entry("sfdc", "Salesforce"),
            Map.entry("netsuite", "NetSuite"),
            Map.entry("workday", "Workday"),
            Map.entry("servicenow", "ServiceNow"),
            Map.entry("sap", "SAP"),
            Map.entry("jms", "JMS Queue"),
            Map.entry("amqp", "AMQP Queue"),
            Map.entry("vm", "VM Queue"),
            Map.entry("kafka", "Kafka"),
            Map.entry("mongo", "MongoDB"),
            Map.entry("redis", "Redis"),
            Map.entry("file", "File System"),
            Map.entry("ftp", "FTP/SFTP"),
            Map.entry("sftp", "FTP/SFTP"),
            Map.entry("s3", "Amazon S3"),
            Map.entry("email", "Email"),
            Map.entry("smtp", "Email"),
            Map.entry("imap", "Email"),
            Map.entry("pop3", "Email"));

    // Connector child elements that are configuration/parameters, not the operation itself.
    private static final Set<String> NON_OPERATION_LOCALS =
            Set.of("config", "connection", "request-connection", "pooling-profile", "reconnection");

    // pom classifiers / heuristics that indicate an Exchange API asset (vs a connector/runtime dep).
    private static final Set<String> API_CLASSIFIERS =
            Set.of("raml", "oas", "http-api", "rest-api", "wsdl");
    private static final Set<String> IGNORED_GROUP_PREFIXES =
            Set.of("org.mule", "com.mulesoft");

    private MuleProjectScanner() {
    }

    /**
     * Scan one project, or a folder of repos. If {@code root} directly contains a {@code pom.xml}
     * it is scanned as a single Mule app; otherwise every descendant directory that contains a
     * {@code pom.xml} with a {@code src/main/mule} folder is scanned. One entry per Mule app.
     */
    public static List<MuleScan> scanAll(Path root) {
        if (Files.isRegularFile(root.resolve("pom.xml"))) {
            return List.of(scan(root));
        }
        List<MuleScan> scans = new ArrayList<>();
        try (Stream<Path> walk = Files.walk(root)) {
            walk.filter(p -> p.getFileName() != null && p.getFileName().toString().equals("pom.xml"))
                    .map(Path::getParent)
                    .filter(dir -> Files.isDirectory(dir.resolve("src/main/mule")))
                    .sorted()
                    .forEach(dir -> scans.add(scan(dir)));
        } catch (IOException e) {
            throw new MuleScanException("Could not scan repos under " + root, e);
        }
        return scans;
    }

    /** Scan a Mule project directory (the one containing {@code pom.xml}). */
    public static MuleScan scan(Path projectDir) {
        Path pom = projectDir.resolve("pom.xml");
        PomInfo pomInfo = Files.isRegularFile(pom) ? parsePom(pom) : new PomInfo("unknown", null, null, List.of());

        // Map a downstream API's declared artifactId to a normalized key for config-ref matching.
        Map<String, String> apiByKey = new LinkedHashMap<>();
        for (String api : pomInfo.apis()) {
            apiByKey.put(normalize(api), api);
        }

        List<MuleScan.InboundEndpoint> endpoints = new ArrayList<>();
        List<MuleScan.OutboundCall> orphanCalls = new ArrayList<>();

        Path muleDir = projectDir.resolve("src/main/mule");
        if (Files.isDirectory(muleDir)) {
            // Read config properties/YAML, then resolve each http:request-config's host to a real
            // downstream API — this is how relationships are actually wired in a Mule project.
            Map<String, String> props = loadProperties(projectDir);
            Map<String, String> configToApi = collectConfigApis(muleDir, props, apiByKey);
            try (Stream<Path> files = Files.walk(muleDir)) {
                files.filter(p -> p.toString().endsWith(".xml"))
                        .sorted()
                        .forEach(p -> scanFlowFile(p, apiByKey, configToApi, endpoints, orphanCalls));
            } catch (IOException e) {
                throw new MuleScanException("Could not scan flows in " + muleDir, e);
            }
        }

        MuleScan.Owner owner = readOwner(projectDir);
        return new MuleScan(pomInfo.artifactId(), pomInfo.groupId(), pomInfo.version(),
                owner, endpoints, pomInfo.apis(), orphanCalls);
    }

    /**
     * Read optional {@code apiguard-owner.yaml} from the project root to attach ownership
     * (team / reviewers / slack) so the blast radius shows who to notify. Absent → empty owner.
     */
    private static MuleScan.Owner readOwner(Path projectDir) {
        for (String name : new String[]{"apiguard-owner.yaml", "apiguard-owner.yml"}) {
            Path file = projectDir.resolve(name);
            if (Files.isRegularFile(file)) {
                try {
                    OwnerFile of = OWNER_YAML.readValue(Files.readString(file), OwnerFile.class);
                    return new MuleScan.Owner(of.ownerTeam,
                            of.reviewers == null ? List.of() : of.reviewers,
                            of.slackChannel, of.sourceRepo);
                } catch (IOException e) {
                    throw new MuleScanException("Could not read " + file, e);
                }
            }
        }
        return MuleScan.Owner.empty();
    }

    private static final com.fasterxml.jackson.databind.ObjectMapper OWNER_YAML =
            new com.fasterxml.jackson.databind.ObjectMapper(
                    new com.fasterxml.jackson.dataformat.yaml.YAMLFactory())
                    .configure(com.fasterxml.jackson.databind.DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    @com.fasterxml.jackson.annotation.JsonIgnoreProperties(ignoreUnknown = true)
    private static final class OwnerFile {
        @com.fasterxml.jackson.annotation.JsonProperty("owner_team")
        public String ownerTeam;
        public List<String> reviewers;
        @com.fasterxml.jackson.annotation.JsonProperty("slack_channel")
        public String slackChannel;
        @com.fasterxml.jackson.annotation.JsonProperty("source_repo")
        public String sourceRepo;
    }

    // ---------------------------------------------------------------- pom

    private record PomInfo(String artifactId, String groupId, String version, List<String> apis) {
    }

    private static PomInfo parsePom(Path pom) {
        try {
            Document doc = builder().parse(pom.toFile());
            Element project = doc.getDocumentElement();

            String artifactId = directChildText(project, "artifactId");
            String groupId = directChildText(project, "groupId");
            String version = directChildText(project, "version");

            List<String> apis = new ArrayList<>();
            Set<String> seen = new LinkedHashSet<>();
            for (Element dep : directChildren(directChild(project, "dependencies"), "dependency")) {
                String depGroup = directChildText(dep, "groupId");
                String depArtifact = directChildText(dep, "artifactId");
                String classifier = directChildText(dep, "classifier");
                String type = directChildText(dep, "type");
                if (depArtifact != null && isApiAsset(depGroup, classifier, type) && seen.add(depArtifact)) {
                    apis.add(depArtifact);
                }
            }
            return new PomInfo(artifactId == null ? "unknown" : artifactId, groupId, version, apis);
        } catch (Exception e) {
            throw new MuleScanException("Could not parse " + pom, e);
        }
    }

    private static boolean isApiAsset(String groupId, String classifier, String type) {
        if (groupId != null) {
            for (String prefix : IGNORED_GROUP_PREFIXES) {
                if (groupId.startsWith(prefix)) {
                    return false;
                }
            }
        }
        if (classifier != null && API_CLASSIFIERS.contains(classifier.toLowerCase())) {
            return true;
        }
        // A zip dependency that isn't a connector is very likely an Exchange API asset.
        return "zip".equalsIgnoreCase(type);
    }

    // ---------------------------------------------------------------- flows

    private static void scanFlowFile(Path file, Map<String, String> apiByKey, Map<String, String> configToApi,
                                     List<MuleScan.InboundEndpoint> endpoints,
                                     List<MuleScan.OutboundCall> orphanCalls) {
        try {
            Document doc = builder().parse(file.toFile());
            for (Element flow : elementsByLocalName(doc.getDocumentElement(), "flow")) {
                String name = flow.getAttribute("name");
                List<MuleScan.OutboundCall> calls = new ArrayList<>();
                for (Element req : elementsByLocalName(flow, "request")) {
                    MuleScan.OutboundCall call = toCall(req, apiByKey, configToApi);
                    if (call != null) {
                        calls.add(call);
                    }
                }
                // End-system (DB / SaaS / queue / file) calls this flow makes through a connector.
                collectBackendCalls(flow, calls);
                // DataWeave field lineage: which downstream response fields this flow reads.
                List<String> dwFields = DataWeaveLineage.referencedFields(flow.getTextContent());
                if (!dwFields.isEmpty()) {
                    calls.replaceAll(c -> c.withFields(dwFields));
                }
                Endpoint parsed = parseEndpointName(name);
                if (parsed != null) {
                    endpoints.add(new MuleScan.InboundEndpoint(parsed.method(), parsed.path(), calls));
                } else {
                    orphanCalls.addAll(calls); // sub-flow / non-APIkit flow
                }
            }
        } catch (Exception e) {
            throw new MuleScanException("Could not parse flow file " + file, e);
        }
    }

    /**
     * Walk a flow and emit one {@link MuleScan.OutboundCall} per end-system operation (a
     * {@code <db:select>}, {@code <salesforce:query>}, {@code <jms:publish>}…). We stop descending
     * once a connector element is reached so its parameter children ({@code db:sql}, {@code db:in-param})
     * are not mistaken for operations of their own.
     */
    private static void collectBackendCalls(Element node, List<MuleScan.OutboundCall> out) {
        for (Element child : childElements(node)) {
            String prefix = child.getPrefix();
            String system = prefix == null ? null : BACKEND_CONNECTORS.get(prefix.toLowerCase());
            if (system != null) {
                String local = child.getLocalName() == null ? "" : child.getLocalName();
                String l = local.toLowerCase();
                boolean isOperation = !NON_OPERATION_LOCALS.contains(l)
                        && !l.endsWith("-config") && !l.endsWith("-connection");
                if (isOperation) {
                    out.add(new MuleScan.OutboundCall(system, local.toUpperCase(), "",
                            child.getAttribute("config-ref")));
                }
                // Either way, don't descend into a connector element's own children.
                continue;
            }
            // Descend through flow-control / transform scopes to find nested connector calls.
            collectBackendCalls(child, out);
        }
    }

    private static MuleScan.OutboundCall toCall(Element request, Map<String, String> apiByKey,
                                                Map<String, String> configToApi) {
        String method = request.getAttribute("method");
        String path = request.getAttribute("path");
        String configRef = request.getAttribute("config-ref");
        if ((method == null || method.isBlank()) && (path == null || path.isBlank())) {
            return null;
        }
        String api = resolveApi(configRef, apiByKey, configToApi);
        return new MuleScan.OutboundCall(api,
                method == null || method.isBlank() ? "GET" : method.toUpperCase(),
                path == null ? "" : path, configRef);
    }

    /**
     * Map an {@code config-ref} to a downstream API. Priority: the host resolved from the matching
     * {@code <http:request-config>} (via properties) → a declared Exchange (pom) API by name → a
     * cleaned-up config name.
     */
    private static String resolveApi(String configRef, Map<String, String> apiByKey, Map<String, String> configToApi) {
        if (configRef == null || configRef.isBlank()) {
            return "unknown-api";
        }
        String key = normalize(configRef);
        // 1) Real host from the config's request-connection (resolved through properties).
        String fromHost = configToApi.get(key);
        if (fromHost != null && !fromHost.isBlank()) {
            return fromHost;
        }
        // 2) Match the config name against a declared Exchange API.
        for (Map.Entry<String, String> e : apiByKey.entrySet()) {
            if (key.equals(e.getKey()) || key.contains(e.getKey()) || e.getKey().contains(key)) {
                return e.getValue();
            }
        }
        // 3) Fall back to a cleaned-up config name so the edge is still meaningful.
        return configRef.replaceAll("(?i)[-_]?config$", "").replaceAll("(?i)HTTP_?Request_?config.*", "");
    }

    // ---------------------------------------------------------------- properties + config hosts

    /** Load {@code *.properties} / {@code *.yaml} / {@code *.yml} under {@code src/main/resources}. */
    private static Map<String, String> loadProperties(Path projectDir) {
        Map<String, String> props = new LinkedHashMap<>();
        Path res = projectDir.resolve("src/main/resources");
        if (!Files.isDirectory(res)) {
            return props;
        }
        try (Stream<Path> files = Files.walk(res)) {
            files.filter(Files::isRegularFile).sorted().forEach(p -> {
                String n = p.getFileName().toString().toLowerCase();
                try {
                    if (n.endsWith(".properties")) {
                        java.util.Properties jp = new java.util.Properties();
                        try (var in = Files.newInputStream(p)) {
                            jp.load(in);
                        }
                        jp.forEach((k, v) -> props.put(k.toString(), v.toString()));
                    } else if (n.endsWith(".yaml") || n.endsWith(".yml")) {
                        flattenYaml("", OWNER_YAML.readTree(Files.readString(p)), props);
                    }
                } catch (Exception ignored) {
                    // A malformed config file shouldn't fail the whole scan.
                }
            });
        } catch (IOException ignored) {
        }
        return props;
    }

    private static void flattenYaml(String prefix, com.fasterxml.jackson.databind.JsonNode node, Map<String, String> out) {
        if (node.isObject()) {
            node.fields().forEachRemaining(e ->
                    flattenYaml(prefix.isEmpty() ? e.getKey() : prefix + "." + e.getKey(), e.getValue(), out));
        } else if (node.isValueNode()) {
            out.put(prefix, node.asText());
        }
    }

    /** Build a map of normalized {@code request-config} name → downstream API, using resolved hosts. */
    private static Map<String, String> collectConfigApis(Path muleDir, Map<String, String> props,
                                                         Map<String, String> apiByKey) {
        Map<String, String> configToApi = new LinkedHashMap<>();
        try (Stream<Path> files = Files.walk(muleDir)) {
            files.filter(p -> p.toString().endsWith(".xml")).forEach(p -> {
                try {
                    Document doc = builder().parse(p.toFile());
                    for (Element cfg : elementsByLocalName(doc.getDocumentElement(), "request-config")) {
                        String name = cfg.getAttribute("name");
                        if (name == null || name.isBlank()) {
                            continue;
                        }
                        String host = null;
                        for (Element conn : elementsByLocalName(cfg, "request-connection")) {
                            host = conn.getAttribute("host");
                            break;
                        }
                        String api = apiFromHost(resolvePlaceholders(host, props), apiByKey);
                        if (api != null) {
                            configToApi.put(normalize(name), api);
                        }
                    }
                } catch (Exception ignored) {
                }
            });
        } catch (IOException ignored) {
        }
        return configToApi;
    }

    /** Resolve {@code ${a.b.c}} placeholders in a value against the properties map (one pass). */
    private static String resolvePlaceholders(String value, Map<String, String> props) {
        if (value == null || !value.contains("${")) {
            return value;
        }
        Matcher m = Pattern.compile("\\$\\{([^}]+)}").matcher(value);
        StringBuilder sb = new StringBuilder();
        while (m.find()) {
            String key = m.group(1).trim();
            m.appendReplacement(sb, Matcher.quoteReplacement(props.getOrDefault(key, m.group())));
        }
        m.appendTail(sb);
        return sb.toString();
    }

    /** Derive an API name from a resolved host, then align it to a declared Exchange API if possible. */
    private static String apiFromHost(String host, Map<String, String> apiByKey) {
        if (host == null || host.isBlank() || host.contains("${")) {
            return null;
        }
        String h = host.replaceAll("^https?://", "");
        int slash = h.indexOf('/');
        if (slash >= 0) {
            h = h.substring(0, slash);
        }
        int colon = h.indexOf(':');
        if (colon >= 0) {
            h = h.substring(0, colon);
        }
        String label = h.contains(".") ? h.substring(0, h.indexOf('.')) : h;
        if (label.isBlank() || label.equalsIgnoreCase("localhost")) {
            return null;
        }
        String key = normalize(label);
        for (Map.Entry<String, String> e : apiByKey.entrySet()) {
            if (key.equals(e.getKey()) || key.contains(e.getKey()) || e.getKey().contains(key)) {
                return e.getValue(); // align to the declared Exchange asset name
            }
        }
        return label; // otherwise the hostname label is the best signal we have
    }

    record Endpoint(String method, String path) {
    }

    /**
     * Parse an APIkit flow name like {@code get:\orders\(orderId):orders-exp-api-config} or
     * {@code post:\orders:application\json:cfg} into {@code POST /orders}.
     * Returns {@code null} when the name isn't an APIkit endpoint (sub-flow, private flow…).
     */
    static Endpoint parseEndpointName(String name) {
        if (name == null || name.isBlank()) {
            return null;
        }
        String[] parts = name.split(":");
        String method = parts[0].trim().toUpperCase();
        if (!HTTP_VERBS.contains(method)) {
            return null;
        }
        // The resource segment is the first part (after the method) that begins with a backslash.
        for (int i = 1; i < parts.length; i++) {
            String seg = parts[i];
            if (seg.startsWith("\\")) {
                String path = seg.replace('\\', '/').replace('(', '{').replace(')', '}');
                if (!path.startsWith("/")) {
                    path = "/" + path;
                }
                return new Endpoint(method, path);
            }
        }
        return new Endpoint(method, "/");
    }

    // ---------------------------------------------------------------- xml helpers

    private static DocumentBuilder builder() throws Exception {
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        f.setNamespaceAware(true);
        f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
        return f.newDocumentBuilder();
    }

    private static String normalize(String s) {
        return s.toLowerCase().replaceAll("[^a-z0-9]", "")
                .replaceAll("config$", "").replaceAll("api$", "");
    }

    private static Element directChild(Element parent, String localName) {
        if (parent == null) {
            return null;
        }
        for (Element e : childElements(parent)) {
            if (localName.equals(e.getLocalName()) || localName.equals(e.getNodeName())) {
                return e;
            }
        }
        return null;
    }

    private static List<Element> directChildren(Element parent, String localName) {
        List<Element> out = new ArrayList<>();
        if (parent == null) {
            return out;
        }
        for (Element e : childElements(parent)) {
            if (localName.equals(e.getLocalName()) || localName.equals(e.getNodeName())) {
                out.add(e);
            }
        }
        return out;
    }

    private static String directChildText(Element parent, String localName) {
        Element child = directChild(parent, localName);
        return child == null ? null : child.getTextContent().trim();
    }

    private static List<Element> childElements(Element parent) {
        List<Element> out = new ArrayList<>();
        NodeList nodes = parent.getChildNodes();
        for (int i = 0; i < nodes.getLength(); i++) {
            Node n = nodes.item(i);
            if (n.getNodeType() == Node.ELEMENT_NODE) {
                out.add((Element) n);
            }
        }
        return out;
    }

    /** All descendant elements (any depth) whose local name matches. */
    private static List<Element> elementsByLocalName(Element root, String localName) {
        List<Element> out = new ArrayList<>();
        collect(root, localName, out, root);
        return out;
    }

    private static void collect(Element current, String localName, List<Element> out, Element root) {
        for (Element child : childElements(current)) {
            String ln = child.getLocalName() != null ? child.getLocalName() : child.getNodeName();
            // Strip a namespace prefix if present in nodeName (e.g. "http:request").
            if (ln.contains(":")) {
                ln = ln.substring(ln.indexOf(':') + 1);
            }
            boolean matches = localName.equals(ln);
            // Don't descend into nested flows when collecting flows themselves.
            if (matches) {
                out.add(child);
            }
            if (!("flow".equals(localName) && matches)) {
                collect(child, localName, out, root);
            }
        }
    }

    /** Thrown when a Mule project cannot be scanned. */
    public static final class MuleScanException extends RuntimeException {
        public MuleScanException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
