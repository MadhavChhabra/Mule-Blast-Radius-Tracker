package com.apiguard.cli;

import picocli.CommandLine.Command;
import picocli.CommandLine.Option;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.concurrent.Callable;

@Command(name = "report", mixinStandardHelpOptions = true,
        description = "Download the estate report (Markdown) from a Wakegraph server.")
public final class ReportCommand implements Callable<Integer> {

    @Option(names = "--server",
            description = "Wakegraph server base URL. Default: $APIGUARD_SERVER or http://localhost:8080.",
            defaultValue = "${env:APIGUARD_SERVER:-http://localhost:8080}")
    String server;

    @Option(names = {"-o", "--out"}, paramLabel = "FILE",
            description = "Write the report here (default: stdout).")
    Path out;

    @Option(names = "--api-key", paramLabel = "KEY",
            description = "API key when the server has auth on. Default: $APIGUARD_API_KEY.",
            defaultValue = "${env:APIGUARD_API_KEY:-}")
    String apiKeyOpt;

    @Override
    public Integer call() throws IOException, InterruptedException {
        String base = server.endsWith("/") ? server.substring(0, server.length() - 1) : server;
        HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
        HttpRequest.Builder rb = HttpRequest.newBuilder(URI.create(base + "/api/report"))
                .timeout(Duration.ofSeconds(60)).GET();
        if (apiKeyOpt != null && !apiKeyOpt.isBlank()) {
            rb.header("X-API-Key", apiKeyOpt.trim());
        }
        HttpRequest request = rb.build();
        HttpResponse<String> response;
        try {
            response = http.send(request, HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            System.err.println("Could not reach Wakegraph at " + base + ": " + e.getMessage());
            return 2;
        }
        if (response.statusCode() != 200) {
            System.err.println("Wakegraph returned HTTP " + response.statusCode());
            return 2;
        }
        if (out == null) {
            System.out.println(response.body());
        } else {
            Files.writeString(out, response.body(), StandardCharsets.UTF_8);
            System.out.println("Estate report written to " + out);
        }
        return 0;
    }
}
