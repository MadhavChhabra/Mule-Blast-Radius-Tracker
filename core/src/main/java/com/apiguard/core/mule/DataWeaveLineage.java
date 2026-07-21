package com.apiguard.core.mule;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
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

public final class DataWeaveLineage {

    private static final Pattern PAYLOAD_CHAIN = Pattern.compile(
            "(?:message\\s*\\.\\s*)?payload((?:\\s*\\.\\s*\"?[A-Za-z_$][\\w$]*\"?|\\s*\\[\\s*\\d+\\s*\\])+)");
    private static final Pattern SEGMENT = Pattern.compile("\"?([A-Za-z_$][\\w$]*)\"?");

    private DataWeaveLineage() {
    }

    public static List<String> referencedFields(String text) {
        Set<String> fields = new LinkedHashSet<>();
        if (text == null || (!text.contains("payload") )) {
            return List.of();
        }
        Matcher chain = PAYLOAD_CHAIN.matcher(text);
        while (chain.find()) {
            Matcher seg = SEGMENT.matcher(chain.group(1));
            while (seg.find()) {
                fields.add(seg.group(1));
            }
        }
        return List.copyOf(fields);
    }

    public static List<String> referencedFieldsInFile(Path file) throws IOException {
        return referencedFields(Files.readString(file, StandardCharsets.UTF_8));
    }

    public static Map<String, List<String>> fieldSitesUnder(Path root) {
        Map<String, Set<String>> sites = new LinkedHashMap<>();
        if (root == null || !Files.isDirectory(root)) {
            return Map.of();
        }
        try (Stream<Path> files = Files.walk(root)) {
            files.filter(p -> p.getFileName() != null
                            && p.getFileName().toString().toLowerCase().endsWith(".dwl"))
                    .sorted()
                    .forEach(p -> {
                        try {
                            String label = root.relativize(p).toString().replace('\\', '/');
                            for (String f : referencedFieldsInFile(p)) {
                                sites.computeIfAbsent(f, k -> new LinkedHashSet<>()).add(label);
                            }
                        } catch (IOException ignored) {
                        }
                    });
        } catch (IOException ignored) {
        }
        Map<String, List<String>> out = new LinkedHashMap<>();
        sites.forEach((k, v) -> out.put(k, new ArrayList<>(v)));
        return out;
    }
}
