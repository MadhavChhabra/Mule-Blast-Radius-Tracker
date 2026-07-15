package com.apiguard.core.mule;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Extracts field lineage from DataWeave. In MuleSoft, an app maps a downstream response into its own
 * shape with DataWeave, so references like {@code payload.customerId} tell us exactly which downstream
 * response fields the app depends on. That turns endpoint-level blast radius into field-level.
 *
 * <p>Deliberately lightweight: we scan for {@code payload}/{@code message.payload} property chains
 * (the downstream response) and collect the referenced field names. This over-approximates rather
 * than under-approximates (safer for a "what might break" tool) and needs no DataWeave runtime.
 */
public final class DataWeaveLineage {

    // payload  followed by one or more  .field  /  ."field"  /  [n]  segments.
    private static final Pattern PAYLOAD_CHAIN = Pattern.compile(
            "(?:message\\s*\\.\\s*)?payload((?:\\s*\\.\\s*\"?[A-Za-z_$][\\w$]*\"?|\\s*\\[\\s*\\d+\\s*\\])+)");
    private static final Pattern SEGMENT = Pattern.compile("\"?([A-Za-z_$][\\w$]*)\"?");

    private DataWeaveLineage() {
    }

    /** All downstream response field names referenced via {@code payload.*} in the given text. */
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
}
