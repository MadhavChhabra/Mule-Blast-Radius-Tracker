package com.apiguard.cli;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.Locale;

@Command(name = "impact", mixinStandardHelpOptions = true,
        description = "Analyze a spec change against a Wakegraph server's estate: blast radius, risk, changelog. CI-friendly.")
public final class ImpactCommand implements java.util.concurrent.Callable<Integer> {

    @Parameters(index = "0", paramLabel = "OLD_OR_NEW", arity = "1",
            description = "Baseline spec path; or, with --base, the current spec to compare against git history.")
    Path firstSpec;

    @Parameters(index = "1", paramLabel = "NEW", arity = "0..1",
            description = "New spec path (omit when using --base).")
    Path newSpecOpt;

    @Option(names = "--base", description = "Git ref (e.g. origin/main) to read the baseline spec from.")
    String baseRef;

    @Option(names = {"-a", "--api"}, required = true,
            description = "API name in the estate (assetId / Maven artifactId).")
    String apiName;

    @Option(names = "--server",
            description = "Wakegraph server base URL. Default: $APIGUARD_SERVER or http://localhost:8080.",
            defaultValue = "${env:APIGUARD_SERVER:-http://localhost:8080}")
    String server;

    @Option(names = "--markdown", paramLabel = "FILE",
            description = "Write a PR-comment Markdown report here ('-' = stdout).")
    String markdownOut;

    @Option(names = "--fail-on", paramLabel = "MODE",
            description = "breaking-impact (default: breaking change hits a known consumer), breaking (any), never.",
            defaultValue = "breaking-impact")
    String failOn;

    @Option(names = "--api-key", paramLabel = "KEY",
            description = "API key when the server has auth on. Default: $APIGUARD_API_KEY.",
            defaultValue = "${env:APIGUARD_API_KEY:-}")
    String apiKeyOpt;

    @Option(names = "--from-label", defaultValue = "before", description = "Label for the baseline version.")
    String fromLabel;

    @Option(names = "--to-label", defaultValue = "after", description = "Label for the new version.")
    String toLabel;

    @Option(names = "--no-color", description = "Disable ANSI colour output.")
    boolean noColor;

    private static final ObjectMapper JSON = new ObjectMapper();

    @Override
    public Integer call() throws IOException, InterruptedException {
        Ansi ansi = new Ansi(!noColor);

        ImpactReport.FailOn mode;
        switch (failOn.toLowerCase(Locale.ROOT)) {
            case "breaking-impact" -> mode = ImpactReport.FailOn.BREAKING_IMPACT;
            case "breaking" -> mode = ImpactReport.FailOn.BREAKING;
            case "never" -> mode = ImpactReport.FailOn.NEVER;
            default -> {
                System.err.println("--fail-on must be breaking-impact, breaking or never.");
                return 2;
            }
        }

        String oldSpec;
        String newSpec;
        if (baseRef != null) {
            newSpec = Files.readString(firstSpec, StandardCharsets.UTF_8);
            oldSpec = GitSpec.showAtRef(firstSpec, baseRef);
        } else {
            if (newSpecOpt == null) {
                System.err.println("Provide NEW spec, or use --base <ref>.");
                return 2;
            }
            oldSpec = Files.readString(firstSpec, StandardCharsets.UTF_8);
            newSpec = Files.readString(newSpecOpt, StandardCharsets.UTF_8);
        }

        ObjectNode body = JSON.createObjectNode();
        body.put("api", apiName);
        body.put("oldSpec", oldSpec);
        body.put("newSpec", newSpec);
        body.put("fromLabel", fromLabel);
        body.put("toLabel", toLabel);
        body.put("notifyPr", false);

        String base = server.endsWith("/") ? server.substring(0, server.length() - 1) : server;
        HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
        HttpRequest.Builder rb = HttpRequest.newBuilder(URI.create(base + "/api/analyze"))
                .timeout(Duration.ofSeconds(60))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JSON.writeValueAsString(body), StandardCharsets.UTF_8));
        if (apiKeyOpt != null && !apiKeyOpt.isBlank()) {
            rb.header("X-API-Key", apiKeyOpt.trim());
        }
        HttpRequest request = rb.build();

        HttpResponse<String> response;
        try {
            response = http.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            System.err.println("Could not reach Wakegraph at " + base + ": " + e.getMessage());
            System.err.println("Set --server or APIGUARD_SERVER to your Wakegraph URL.");
            return 2;
        }
        if (response.statusCode() != 200) {
            System.err.println("Wakegraph returned HTTP " + response.statusCode() + ": "
                    + firstLine(response.body()));
            return 2;
        }

        JsonNode result = JSON.readTree(response.body());
        ImpactReport.renderConsole(result, ansi, System.out);

        if (markdownOut != null) {
            String md = ImpactReport.renderMarkdown(result);
            if (markdownOut.equals("-")) {
                System.out.println();
                System.out.println(md);
            } else {
                Files.writeString(Path.of(markdownOut), md, StandardCharsets.UTF_8);
                System.out.println(ansi.dim("Markdown report written to " + markdownOut));
            }
        }
        return ImpactReport.exitCode(result, mode);
    }

    private static String firstLine(String s) {
        if (s == null) {
            return "";
        }
        int nl = s.indexOf('\n');
        String line = nl > 0 ? s.substring(0, nl) : s;
        return line.length() > 300 ? line.substring(0, 300) + "…" : line;
    }
}
