package com.apiguard.core.spec;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.responses.ApiResponse;

import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.Map;

/**
 * The queryable "surface" of an API spec: for each endpoint ({@code METHOD /path}), the set of
 * response field names a consumer could read. This is what a developer sees when they ask
 * "which field am I about to change?" — the candidate fields for change-propagation.
 *
 * <p>Fields are the top-level property names of the 2xx JSON response schema (arrays unwrapped to
 * their item object), which is exactly the granularity the blast-radius resolver and DataWeave
 * lineage track ({@code payload.field}). Endpoint keys match the manifest format so they resolve
 * directly.
 */
public final class SpecSurface {

    private SpecSurface() {
    }

    /** endpoint ({@code "GET /orders/{id}"}) -> ordered set of response field names. */
    public static Map<String, LinkedHashSet<String>> responseFields(OpenAPI api) {
        Map<String, LinkedHashSet<String>> out = new LinkedHashMap<>();
        if (api == null || api.getPaths() == null) {
            return out;
        }
        api.getPaths().forEach((path, item) -> {
            for (Map.Entry<PathItem.HttpMethod, Operation> op : item.readOperationsMap().entrySet()) {
                String endpoint = op.getKey().name() + " " + path;
                LinkedHashSet<String> fields = out.computeIfAbsent(endpoint, k -> new LinkedHashSet<>());
                collectResponseFields(op.getValue(), fields);
            }
        });
        return out;
    }

    private static void collectResponseFields(Operation op, LinkedHashSet<String> fields) {
        if (op == null || op.getResponses() == null) {
            return;
        }
        op.getResponses().forEach((code, response) -> {
            if (isSuccess(code)) {
                collectFromContent(response, fields);
            }
        });
    }

    private static boolean isSuccess(String code) {
        return code != null && (code.startsWith("2") || code.equalsIgnoreCase("default"));
    }

    private static void collectFromContent(ApiResponse response, LinkedHashSet<String> fields) {
        Content content = response == null ? null : response.getContent();
        if (content == null) {
            return;
        }
        MediaType media = content.get("application/json");
        if (media == null && !content.isEmpty()) {
            media = content.values().iterator().next(); // fall back to whatever media type exists
        }
        if (media != null) {
            collectSchemaProperties(media.getSchema(), fields);
        }
    }

    @SuppressWarnings("rawtypes")
    private static void collectSchemaProperties(Schema schema, LinkedHashSet<String> fields) {
        if (schema == null) {
            return;
        }
        // Unwrap an array response to the object it contains.
        if (schema.getItems() != null) {
            collectSchemaProperties(schema.getItems(), fields);
            return;
        }
        Map<String, Schema> props = schema.getProperties();
        if (props != null) {
            fields.addAll(props.keySet());
        }
    }
}
