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

public final class SpecSurface {

    private SpecSurface() {
    }

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
            media = content.values().iterator().next();
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
