package com.apiguard.core.blast;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.dataformat.yaml.YAMLFactory;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.stream.Stream;

/** Loads {@code apiguard-deps.yaml} (consumer) and producer {@code sources} manifests from disk or strings. */
public final class ManifestLoader {

    private static final ObjectMapper YAML = new ObjectMapper(new YAMLFactory())
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    private ManifestLoader() {
    }

    public static DependencyManifest loadDependency(String yaml) {
        try {
            return YAML.readValue(yaml, DependencyManifest.class);
        } catch (IOException e) {
            throw new UncheckedIOException("Invalid dependency manifest", e);
        }
    }

    public static FieldSourceManifest loadSources(String yaml) {
        try {
            return YAML.readValue(yaml, FieldSourceManifest.class);
        } catch (IOException e) {
            throw new UncheckedIOException("Invalid sources manifest", e);
        }
    }

    /**
     * Discover manifests under a directory tree. Files named {@code apiguard-deps.yaml} are treated
     * as consumer manifests; files named {@code apiguard-sources.yaml} as producer lineage.
     */
    public static Loaded discover(Path root) {
        List<DependencyManifest> consumers = new ArrayList<>();
        List<FieldSourceManifest> sources = new ArrayList<>();
        if (!Files.isDirectory(root)) {
            return new Loaded(consumers, sources);
        }
        try (Stream<Path> walk = Files.walk(root)) {
            walk.filter(Files::isRegularFile).forEach(p -> {
                String name = p.getFileName().toString();
                try {
                    String content = Files.readString(p, StandardCharsets.UTF_8);
                    if (name.equals("apiguard-deps.yaml") || name.equals("apiguard-deps.yml")) {
                        consumers.add(loadDependency(content));
                    } else if (name.equals("apiguard-sources.yaml") || name.equals("apiguard-sources.yml")) {
                        sources.add(loadSources(content));
                    }
                } catch (IOException e) {
                    throw new UncheckedIOException("Could not read manifest " + p, e);
                }
            });
        } catch (IOException e) {
            throw new UncheckedIOException("Could not scan " + root, e);
        }
        return new Loaded(consumers, sources);
    }

    public record Loaded(List<DependencyManifest> consumers, List<FieldSourceManifest> sources) {
    }
}
