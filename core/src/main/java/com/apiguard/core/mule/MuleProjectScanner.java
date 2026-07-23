package com.apiguard.core.mule;

import com.apiguard.core.spec.RamlLoader;
import com.apiguard.core.spec.SpecLoader;
import io.swagger.v3.core.util.Yaml;
import io.swagger.v3.oas.models.OpenAPI;
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
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

public final class MuleProjectScanner {

    private static final Set<String> HTTP_VERBS =
            Set.of("GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS");

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

    private static final Set<String> NON_OPERATION_LOCALS =
            Set.of("config", "connection", "request-connection", "pooling-profile", "reconnection");

    private static final Set<String> API_CLASSIFIERS =
            Set.of("raml", "oas", "http-api", "rest-api", "wsdl");
    private static final Set<String> IGNORED_GROUP_PREFIXES =
            Set.of("org.mule", "com.mulesoft");

    private MuleProjectScanner() {
    }

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

    public static MuleScan scan(Path projectDir) {
        Path pom = projectDir.resolve("pom.xml");
        PomInfo pomInfo = Files.isRegularFile(pom) ? parsePom(pom) : new PomInfo("unknown", null, null, List.of());

        Map<String, String> apiByKey = new LinkedHashMap<>();
        for (String api : pomInfo.apis()) {
            apiByKey.put(normalize(api), api);
        }

        List<MuleScan.InboundEndpoint> endpoints = new ArrayList<>();
        List<MuleScan.OutboundCall> orphanCalls = new ArrayList<>();
        List<MuleScan.ConfigDriftWarning> configDrift = new ArrayList<>();

        Path muleDir = projectDir.resolve("src/main/mule");
        if (Files.isDirectory(muleDir)) {

            Map<String, String> props = loadProperties(projectDir);
            Map<String, String> configToApi = collectConfigApis(muleDir, props, apiByKey, configDrift);
            try (Stream<Path> files = Files.walk(muleDir)) {
                files.filter(p -> p.toString().endsWith(".xml"))
                        .sorted()
                        .forEach(p -> scanFlowFile(p, apiByKey, configToApi, endpoints, orphanCalls));
            } catch (IOException e) {
                throw new MuleScanException("Could not scan flows in " + muleDir, e);
            }
        }

        MuleScan.Owner owner = readOwner(projectDir);
        String apiSpec = captureApiSpec(projectDir);
        return new MuleScan(pomInfo.artifactId(), pomInfo.groupId(), pomInfo.version(),
                owner, endpoints, pomInfo.apis(), orphanCalls, configDrift, apiSpec);
    }

    static String captureApiSpec(Path projectDir) {
        try {
            Path spec = findSpecFile(projectDir);
            if (spec == null) {
                return null;
            }
            String content = Files.readString(spec);
            OpenAPI api = content.stripLeading().startsWith("#%RAML")
                    ? RamlLoader.loadFile(spec)
                    : SpecLoader.loadFile(spec);
            if (api == null || api.getPaths() == null || api.getPaths().isEmpty()) {
                return null;
            }
            return Yaml.pretty(api);
        } catch (Exception e) {
            return null;
        }
    }

    private static Path findSpecFile(Path projectDir) {
        Path resources = projectDir.resolve("src/main/resources");
        Path fromApikit = specFromApikit(projectDir, resources);
        if (fromApikit != null) {
            return fromApikit;
        }
        return findRootRaml(resources);
    }

    private static Path specFromApikit(Path projectDir, Path resources) {
        Path muleDir = projectDir.resolve("src/main/mule");
        if (!Files.isDirectory(muleDir)) {
            return null;
        }
        try (Stream<Path> files = Files.walk(muleDir)) {
            for (Path xml : files.filter(p -> p.toString().endsWith(".xml")).sorted().toList()) {
                try {
                    Document doc = builder().parse(xml.toFile());
                    for (Element cfg : elementsByLocalName(doc.getDocumentElement(), "config")) {
                        String prefix = cfg.getPrefix();
                        String ns = cfg.getNamespaceURI();
                        boolean apikit = (prefix != null && prefix.toLowerCase().contains("apikit"))
                                || (ns != null && ns.contains("apikit"));
                        if (!apikit) {
                            continue;
                        }
                        String ref = firstNonBlank(cfg.getAttribute("api"),
                                cfg.getAttribute("raml"), cfg.getAttribute("raml-uri"));
                        if (ref == null || ref.startsWith("resource::")) {
                            continue;
                        }
                        for (Path base : List.of(resources, projectDir)) {
                            Path candidate = base.resolve(ref).normalize();
                            if (Files.isRegularFile(candidate)) {
                                return candidate;
                            }
                        }
                    }
                } catch (Exception ignored) {
                }
            }
        } catch (IOException ignored) {
        }
        return null;
    }

    private static Path findRootRaml(Path resources) {
        if (!Files.isDirectory(resources)) {
            return null;
        }
        try (Stream<Path> walk = Files.walk(resources)) {
            return walk.filter(Files::isRegularFile)
                    .filter(p -> p.getFileName().toString().toLowerCase().endsWith(".raml"))
                    .min(Comparator.comparingInt(
                                    (Path p) -> p.getFileName().toString().equalsIgnoreCase("api.raml") ? 0 : 1)
                            .thenComparingInt(Path::getNameCount))
                    .orElse(null);
        } catch (IOException e) {
            return null;
        }
    }

    private static String firstNonBlank(String... values) {
        for (String v : values) {
            if (v != null && !v.isBlank()) {
                return v;
            }
        }
        return null;
    }

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

        return "zip".equalsIgnoreCase(type);
    }

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

                collectBackendCalls(flow, calls);

                List<String> dwFields = DataWeaveLineage.referencedFields(flow.getTextContent());
                if (!dwFields.isEmpty()) {
                    calls.replaceAll(c -> c.withFields(dwFields));
                }
                Endpoint parsed = parseEndpointName(name);
                if (parsed != null) {
                    endpoints.add(new MuleScan.InboundEndpoint(parsed.method(), parsed.path(), calls));
                } else {
                    orphanCalls.addAll(calls);
                }
            }
        } catch (Exception e) {
            throw new MuleScanException("Could not parse flow file " + file, e);
        }
    }

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

                continue;
            }

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

    private static String resolveApi(String configRef, Map<String, String> apiByKey, Map<String, String> configToApi) {
        if (configRef == null || configRef.isBlank()) {
            return "unknown-api";
        }
        String key = normalize(configRef);

        String fromHost = configToApi.get(key);
        if (fromHost != null && !fromHost.isBlank()) {
            return fromHost;
        }

        for (Map.Entry<String, String> e : apiByKey.entrySet()) {
            if (key.equals(e.getKey()) || key.contains(e.getKey()) || e.getKey().contains(key)) {
                return e.getValue();
            }
        }

        return configRef.replaceAll("(?i)[-_]?config$", "").replaceAll("(?i)HTTP_?Request_?config.*", "");
    }

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

    private static Map<String, String> collectConfigApis(Path muleDir, Map<String, String> props,
                                                         Map<String, String> apiByKey,
                                                         List<MuleScan.ConfigDriftWarning> configDrift) {
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
                        String resolved = resolvePlaceholders(host, props);
                        String unresolved = unresolvedPlaceholder(resolved);
                        if (unresolved != null) {
                            configDrift.add(new MuleScan.ConfigDriftWarning(name, host, unresolved));
                        }
                        String api = apiFromHost(resolved, apiByKey);
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

    private static String unresolvedPlaceholder(String value) {
        if (value == null) {
            return null;
        }
        Matcher m = Pattern.compile("\\$\\{([^}]+)}").matcher(value);
        return m.find() ? "${" + m.group(1).trim() + "}" : null;
    }

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
                return e.getValue();
            }
        }
        return label;
    }

    record Endpoint(String method, String path) {
    }

    static Endpoint parseEndpointName(String name) {
        if (name == null || name.isBlank()) {
            return null;
        }
        String[] parts = name.split(":");
        String method = parts[0].trim().toUpperCase();
        if (!HTTP_VERBS.contains(method)) {
            return null;
        }

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

    private static List<Element> elementsByLocalName(Element root, String localName) {
        List<Element> out = new ArrayList<>();
        collect(root, localName, out, root);
        return out;
    }

    private static void collect(Element current, String localName, List<Element> out, Element root) {
        for (Element child : childElements(current)) {
            String ln = child.getLocalName() != null ? child.getLocalName() : child.getNodeName();

            if (ln.contains(":")) {
                ln = ln.substring(ln.indexOf(':') + 1);
            }
            boolean matches = localName.equals(ln);

            if (matches) {
                out.add(child);
            }
            if (!("flow".equals(localName) && matches)) {
                collect(child, localName, out, root);
            }
        }
    }

    public static final class MuleScanException extends RuntimeException {
        public MuleScanException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
