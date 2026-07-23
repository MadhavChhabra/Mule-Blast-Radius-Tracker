package com.apiguard.server.service;

import com.apiguard.core.spec.RamlLoader;
import com.apiguard.core.spec.SpecLoader;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.swagger.v3.core.util.Yaml;
import io.swagger.v3.oas.models.OpenAPI;
import org.springframework.stereotype.Service;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

@Service
public class SpecArchiveService {

    private final ObjectMapper json = new ObjectMapper();

    public record ExtractedSpec(String title, String version, String spec) {
    }

    public ExtractedSpec fromZip(InputStream zipStream) {
        Path tmp = null;
        try {
            tmp = Files.createTempDirectory("apiguard-raml-");
            unzip(zipStream, tmp);
            Path root = findRootSpec(tmp);
            if (root == null) {
                throw new IllegalArgumentException(
                        "No RAML or OpenAPI spec found in the zip. Upload an Exchange RAML/OAS asset.");
            }
            return flatten(root);
        } catch (IOException e) {
            throw new IllegalArgumentException("Could not read the uploaded zip: " + e.getMessage());
        } finally {
            deleteQuietly(tmp);
        }
    }

    public ExtractedSpec fromBytes(byte[] bytes) {
        if (bytes == null || bytes.length == 0) {
            throw new IllegalArgumentException("empty spec content");
        }
        if (bytes.length >= 2 && bytes[0] == 'P' && bytes[1] == 'K') {
            return fromZip(new ByteArrayInputStream(bytes));
        }
        String text = new String(bytes, StandardCharsets.UTF_8);
        OpenAPI api = text.stripLeading().startsWith("#%RAML")
                ? RamlLoader.loadString(text)
                : SpecLoader.loadString(text);
        return toExtracted(api);
    }

    private ExtractedSpec flatten(Path specFile) {
        String name = specFile.getFileName().toString().toLowerCase();
        OpenAPI api = name.endsWith(".raml") ? RamlLoader.loadFile(specFile) : SpecLoader.loadFile(specFile);
        return toExtracted(api);
    }

    private static ExtractedSpec toExtracted(OpenAPI api) {
        if (api == null) {
            throw new IllegalArgumentException("not a recognizable RAML/OpenAPI spec");
        }
        String title = api.getInfo() != null ? api.getInfo().getTitle() : "API";
        String version = api.getInfo() != null ? api.getInfo().getVersion() : null;
        return new ExtractedSpec(title, version, Yaml.pretty(api));
    }

    private void unzip(InputStream in, Path target) throws IOException {
        try (ZipInputStream zip = new ZipInputStream(in)) {
            ZipEntry entry;
            while ((entry = zip.getNextEntry()) != null) {
                Path resolved = target.resolve(entry.getName()).normalize();
                if (!resolved.startsWith(target)) {
                    continue;
                }
                if (entry.isDirectory()) {
                    Files.createDirectories(resolved);
                } else {
                    Files.createDirectories(resolved.getParent());
                    Files.copy(zip, resolved);
                }
                zip.closeEntry();
            }
        }
    }

    private Path findRootSpec(Path dir) throws IOException {

        try (Stream<Path> walk = Files.walk(dir)) {
            Path exchange = walk.filter(p -> p.getFileName().toString().equals("exchange.json")).findFirst().orElse(null);
            if (exchange != null) {
                JsonNode node = json.readTree(Files.readString(exchange));
                String main = node.path("main").asText(null);
                if (main != null && !main.isBlank()) {
                    Path candidate = exchange.getParent().resolve(main).normalize();
                    if (Files.isRegularFile(candidate)) {
                        return candidate;
                    }
                }
            }
        }

        try (Stream<Path> walk = Files.walk(dir)) {
            List<Path> ramls = walk.filter(p -> p.getFileName().toString().toLowerCase().endsWith(".raml"))
                    .sorted(Comparator.comparingInt((Path p) -> p.getNameCount())
                            .thenComparing(p -> p.getFileName().toString().equalsIgnoreCase("api.raml") ? 0 : 1))
                    .toList();
            if (!ramls.isEmpty()) {
                return ramls.get(0);
            }
        }

        try (Stream<Path> walk = Files.walk(dir)) {
            return walk.filter(Files::isRegularFile)
                    .filter(SpecArchiveService::looksLikeOpenApiFile)
                    .min(Comparator.comparingInt(Path::getNameCount))
                    .orElse(null);
        }
    }

    private static boolean looksLikeOpenApiFile(Path p) {
        String n = p.getFileName().toString().toLowerCase();
        if (!n.endsWith(".yaml") && !n.endsWith(".yml") && !n.endsWith(".json")) {
            return false;
        }
        try (var reader = Files.newBufferedReader(p)) {
            char[] buf = new char[512];
            int read = reader.read(buf);
            String head = read > 0 ? new String(buf, 0, read).toLowerCase() : "";
            return head.contains("openapi") || head.contains("swagger");
        } catch (IOException e) {
            return false;
        }
    }

    private static void deleteQuietly(Path dir) {
        if (dir == null) {
            return;
        }
        try (Stream<Path> walk = Files.walk(dir)) {
            walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException ignored) {
                }
            });
        } catch (IOException ignored) {
        }
    }
}
