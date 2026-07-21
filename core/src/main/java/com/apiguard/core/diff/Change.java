package com.apiguard.core.diff;

import java.util.Objects;

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
