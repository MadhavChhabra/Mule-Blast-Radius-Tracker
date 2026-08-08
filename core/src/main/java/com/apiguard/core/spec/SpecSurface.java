package com.apiguard.core.spec;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.parameters.RequestBody;
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

    /// Fields a caller has to *send*. A new required request field breaks every caller, but nothing
    /// in DataWeave lineage can prove who sends what — so the answer here is endpoint-level: whoever
    /// calls this endpoint has to change.
    public static Map<String, LinkedHashSet<String>> requestFields(OpenAPI api) {
        Map<String, LinkedHashSet<String>> out = new LinkedHashMap<>();
        if (api == null || api.getPaths() == null) {
            return out;
        }
        api.getPaths().forEach((path, item) -> {
            for (Map.Entry<PathItem.HttpMethod, Operation> op : item.readOperationsMap().entrySet()) {
                LinkedHashSet<String> fields = new LinkedHashSet<>();
                RequestBody body = op.getValue() == null ? null : op.getValue().getRequestBody();
                if (body != null) {
                    collectFromContent(body.getContent(), fields);
                }
                if (!fields.isEmpty()) {
                    out.computeIfAbsent(op.getKey().name() + " " + path, k -> new LinkedHashSet<>())
                            .addAll(fields);
                }
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
        collectFromContent(response == null ? null : response.getContent(), fields);
    }

    private static void collectFromContent(Content content, LinkedHashSet<String> fields) {
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
