package com.apiguard.core.mule;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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
}
