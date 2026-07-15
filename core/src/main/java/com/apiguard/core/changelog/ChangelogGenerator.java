package com.apiguard.core.changelog;

import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.ChangeKind;
import com.apiguard.core.diff.Classification;

import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;

/**
 * Renders a classified diff into a categorized Markdown changelog
 * (Breaking / Added / Changed / Deprecated / Removed), following the
 * "Keep a Changelog" convention with a dedicated Breaking section on top.
 */
public final class ChangelogGenerator {

    /** Changelog categories, in display order. */
    private enum Category {
        BREAKING("⚠️ Breaking Changes"),
        ADDED("Added"),
        CHANGED("Changed"),
        REMOVED("Removed"),
        DEPRECATED("Deprecated");

        final String heading;

        Category(String heading) {
            this.heading = heading;
        }
    }

    public String generate(List<Change> changes) {
        return generate(changes, null);
    }

    /**
     * @param versionLabel optional heading like {@code "v2.0.0 (2026-07-11)"}; when null no version header is emitted.
     */
    public String generate(List<Change> changes, String versionLabel) {
        Map<Category, List<Change>> buckets = new EnumMap<>(Category.class);
        for (Category c : Category.values()) {
            buckets.put(c, new ArrayList<>());
        }
        for (Change change : changes) {
            buckets.get(categorize(change)).add(change);
        }

        StringBuilder sb = new StringBuilder();
        sb.append("# Changelog\n\n");
        if (versionLabel != null && !versionLabel.isBlank()) {
            sb.append("## ").append(versionLabel).append("\n\n");
        }

        long breaking = changes.stream().filter(Change::isBreaking).count();
        sb.append("_")
                .append(changes.size()).append(changes.size() == 1 ? " change" : " changes")
                .append(", ").append(breaking).append(breaking == 1 ? " breaking" : " breaking")
                .append("._\n\n");

        boolean any = false;
        for (Category category : Category.values()) {
            List<Change> items = buckets.get(category);
            if (items.isEmpty()) {
                continue;
            }
            any = true;
            sb.append("### ").append(category.heading).append("\n\n");
            for (Change change : items) {
                sb.append("- ").append(line(change)).append('\n');
            }
            sb.append('\n');
        }
        if (!any) {
            sb.append("_No API changes detected._\n");
        }
        return sb.toString().stripTrailing() + "\n";
    }

    private String line(Change change) {
        StringBuilder sb = new StringBuilder();
        if (change.endpoint() != null) {
            sb.append("**`").append(change.endpoint()).append("`** — ");
        }
        sb.append(change.description() != null ? change.description() : change.kind().label());
        if (change.isBreaking()) {
            String migration = migrationHint(change);
            if (migration != null) {
                sb.append(" _(").append(migration).append(")_");
            }
        }
        return sb.toString();
    }

    private static Category categorize(Change change) {
        if (change.classification() == Classification.BREAKING) {
            return Category.BREAKING;
        }
        ChangeKind kind = change.kind();
        return switch (kind) {
            case ENDPOINT_ADDED, OPERATION_ADDED, PARAM_ADDED_OPTIONAL,
                 REQUEST_FIELD_ADDED_OPTIONAL, RESPONSE_FIELD_ADDED,
                 REQUEST_ENUM_VALUE_ADDED, RESPONSE_STATUS_ADDED -> Category.ADDED;
            case REQUEST_FIELD_REMOVED, PARAM_REMOVED, RESPONSE_ENUM_VALUE_REMOVED -> Category.REMOVED;
            default -> Category.CHANGED;
        };
    }

    private static String migrationHint(Change change) {
        return switch (change.kind()) {
            case RESPONSE_FIELD_REMOVED -> "consumers reading this field must stop relying on it";
            case ENDPOINT_REMOVED, OPERATION_REMOVED -> "migrate callers to the replacement operation";
            case REQUEST_FIELD_ADDED_REQUIRED, PARAM_ADDED_REQUIRED, REQUEST_FIELD_MADE_REQUIRED, PARAM_MADE_REQUIRED ->
                    "callers must now supply this value";
            case FIELD_TYPE_CHANGED -> "update client models to the new type";
            case REQUEST_ENUM_VALUE_REMOVED -> "callers sending the old value will be rejected";
            case RESPONSE_ENUM_VALUE_ADDED -> "consumers must handle the new value";
            case AUTH_TIGHTENED -> "callers must now authenticate";
            default -> null;
        };
    }
}
