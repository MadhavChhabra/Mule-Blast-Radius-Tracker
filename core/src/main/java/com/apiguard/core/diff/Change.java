package com.apiguard.core.diff;

import java.util.Objects;

/**
 * A single semantic change detected between two OpenAPI specs.
 *
 * @param classification breaking / non-breaking / additive
 * @param kind           the specific rule that fired
 * @param endpoint       human-readable operation, e.g. {@code "GET /orders/{id}"} (may be {@code null} for spec-level changes)
 * @param jsonPointer    a JSON-pointer-ish path into the spec, e.g. {@code "response.200.customerId"}
 * @param field          the leaf field or parameter name involved, if any (e.g. {@code "customerId"})
 * @param description    a short human-readable explanation
 */
public record Change(
        Classification classification,
        ChangeKind kind,
        String endpoint,
        String jsonPointer,
        String field,
        String description
) {
    public Change {
        Objects.requireNonNull(classification, "classification");
        Objects.requireNonNull(kind, "kind");
    }

    public static Change of(Classification classification, ChangeKind kind,
                            String endpoint, String jsonPointer, String field, String description) {
        return new Change(classification, kind, endpoint, jsonPointer, field, description);
    }

    public boolean isBreaking() {
        return classification == Classification.BREAKING;
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        sb.append(String.format("%-13s", classification));
        if (endpoint != null) {
            sb.append(endpoint).append("  ");
        }
        if (jsonPointer != null) {
            sb.append(jsonPointer).append("  ");
        }
        sb.append('(').append(description != null ? description : kind.label()).append(')');
        return sb.toString();
    }
}
