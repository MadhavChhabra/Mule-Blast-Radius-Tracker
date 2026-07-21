package com.apiguard.server.service;

import com.apiguard.core.spec.RamlLoader;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.swagger.v3.core.util.Yaml;
import io.swagger.v3.oas.models.OpenAPI;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.io.InputStream;
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
            Path root = findRootRaml(tmp);
            if (root == null) {
                throw new IllegalArgumentException(
                        "No .raml found in the zip. Upload an Exchange RAML asset (with its exchange.json / api.raml).");
            }
            OpenAPI api = RamlLoader.loadFile(root);
            String title = api.getInfo() != null ? api.getInfo().getTitle() : "API";
            String version = api.getInfo() != null ? api.getInfo().getVersion() : null;
            return new ExtractedSpec(title, version, Yaml.pretty(api));
        } catch (IOException e) {
            throw new IllegalArgumentException("Could not read the uploaded zip: " + e.getMessage());
        } finally {
            deleteQuietly(tmp);
        }
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

    private Path findRootRaml(Path dir) throws IOException {

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
            return ramls.isEmpty() ? null : ramls.get(0);
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
