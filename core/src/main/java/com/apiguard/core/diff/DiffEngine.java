package com.apiguard.core.diff;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.media.ComposedSchema;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.parameters.Parameter;
import io.swagger.v3.oas.models.parameters.RequestBody;
import io.swagger.v3.oas.models.responses.ApiResponse;
import io.swagger.v3.oas.models.responses.ApiResponses;
import io.swagger.v3.oas.models.security.SecurityRequirement;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.TreeSet;

/**
 * The semantic diff engine — the heart of APIGuard.
 *
 * <p>It walks two parsed {@link OpenAPI} models and emits a list of {@link Change}s,
 * each classified {@link Classification#BREAKING}, {@link Classification#NON_BREAKING}
 * or {@link Classification#ADDITIVE}.
 *
 * <h2>The governing principle: request/response asymmetry</h2>
 * <ul>
 *   <li><b>Request side</b> (parameters, request body) — what the server <i>accepts</i>.
 *       Widening it (new optional field, extra accepted enum value) is <b>safe</b>.
 *       Narrowing it (new required field, removed accepted enum value, tightened type)
 *       is <b>breaking</b> because previously-valid callers are now rejected.</li>
 *   <li><b>Response side</b> (response body) — what the server <i>returns</i>.
 *       Removing a field or changing its type is <b>breaking</b>. Even <i>widening</i> a
 *       response enum is breaking, because a strict consumer may not handle the new value.</li>
 * </ul>
 * Narrowing either side is breaking; that single rule explains most of the classifications below.
 */
public final class DiffEngine {

    /** Which side of the contract a schema sits on — this decides the classification. */
    private enum Side {REQUEST, RESPONSE}

    private static final int MAX_DEPTH = 40;

    public List<Change> diff(OpenAPI oldApi, OpenAPI newApi) {
        Objects.requireNonNull(oldApi, "oldApi");
        Objects.requireNonNull(newApi, "newApi");

        List<Change> changes = new ArrayList<>();

        Map<String, PathItem> oldPaths = oldApi.getPaths() != null ? oldApi.getPaths() : Map.of();
        Map<String, PathItem> newPaths = newApi.getPaths() != null ? newApi.getPaths() : Map.of();

        for (String path : union(oldPaths.keySet(), newPaths.keySet())) {
            PathItem oldItem = oldPaths.get(path);
            PathItem newItem = newPaths.get(path);

            if (oldItem != null && newItem == null) {
                changes.add(Change.of(Classification.BREAKING, ChangeKind.ENDPOINT_REMOVED,
                        path, path, null, "Path '" + path + "' was removed"));
                continue;
            }
            if (oldItem == null && newItem != null) {
                changes.add(Change.of(Classification.ADDITIVE, ChangeKind.ENDPOINT_ADDED,
                        path, path, null, "Path '" + path + "' was added"));
                continue;
            }

            diffPathItem(path, oldItem, newItem, oldApi, newApi, changes);
        }

        return changes;
    }

    // ---------------------------------------------------------------- operations

    private void diffPathItem(String path, PathItem oldItem, PathItem newItem,
                              OpenAPI oldApi, OpenAPI newApi, List<Change> out) {
        Map<PathItem.HttpMethod, Operation> oldOps = oldItem.readOperationsMap();
        Map<PathItem.HttpMethod, Operation> newOps = newItem.readOperationsMap();

        Set<PathItem.HttpMethod> methods = new TreeSet<>();
        methods.addAll(oldOps.keySet());
        methods.addAll(newOps.keySet());

        for (PathItem.HttpMethod method : methods) {
            String endpoint = method + " " + path;
            Operation oldOp = oldOps.get(method);
            Operation newOp = newOps.get(method);

            if (oldOp != null && newOp == null) {
                out.add(Change.of(Classification.BREAKING, ChangeKind.OPERATION_REMOVED,
                        endpoint, endpoint, null, "Operation '" + endpoint + "' was removed"));
                continue;
            }
            if (oldOp == null && newOp != null) {
                out.add(Change.of(Classification.ADDITIVE, ChangeKind.OPERATION_ADDED,
                        endpoint, endpoint, null, "Operation '" + endpoint + "' was added"));
                continue;
            }

            diffOperation(endpoint, oldOp, newOp, oldApi, newApi, out);
        }
    }

    private void diffOperation(String endpoint, Operation oldOp, Operation newOp,
                               OpenAPI oldApi, OpenAPI newApi, List<Change> out) {
        diffParameters(endpoint, oldOp, newOp, out);
        diffRequestBody(endpoint, oldOp.getRequestBody(), newOp.getRequestBody(), out);
        diffResponses(endpoint, oldOp.getResponses(), newOp.getResponses(), out);
        diffSecurity(endpoint, effectiveSecurity(oldOp, oldApi), effectiveSecurity(newOp, newApi), out);
    }

    // ---------------------------------------------------------------- parameters

    private void diffParameters(String endpoint, Operation oldOp, Operation newOp, List<Change> out) {
        Map<String, Parameter> oldParams = indexParams(oldOp.getParameters());
        Map<String, Parameter> newParams = indexParams(newOp.getParameters());

        for (String key : union(oldParams.keySet(), newParams.keySet())) {
            Parameter o = oldParams.get(key);
            Parameter n = newParams.get(key);
            String name = key.substring(key.indexOf(':') + 1);
            String pointer = "param." + name;

            if (o == null) { // added
                if (isRequired(n.getRequired())) {
                    out.add(Change.of(Classification.BREAKING, ChangeKind.PARAM_ADDED_REQUIRED,
                            endpoint, pointer, name, "Required " + n.getIn() + " parameter '" + name + "' added"));
                } else {
                    out.add(Change.of(Classification.ADDITIVE, ChangeKind.PARAM_ADDED_OPTIONAL,
                            endpoint, pointer, name, "Optional " + n.getIn() + " parameter '" + name + "' added"));
                }
                continue;
            }
            if (n == null) { // removed
                boolean wasRequired = isRequired(o.getRequired());
                out.add(Change.of(wasRequired ? Classification.BREAKING : Classification.NON_BREAKING,
                        ChangeKind.PARAM_REMOVED, endpoint, pointer, name,
                        (wasRequired ? "Required " : "Optional ") + o.getIn() + " parameter '" + name + "' removed"));
                continue;
            }

            boolean wasRequired = isRequired(o.getRequired());
            boolean nowRequired = isRequired(n.getRequired());
            if (!wasRequired && nowRequired) {
                out.add(Change.of(Classification.BREAKING, ChangeKind.PARAM_MADE_REQUIRED,
                        endpoint, pointer, name, "Parameter '" + name + "' is now required"));
            } else if (wasRequired && !nowRequired) {
                out.add(Change.of(Classification.NON_BREAKING, ChangeKind.PARAM_MADE_OPTIONAL,
                        endpoint, pointer, name, "Parameter '" + name + "' is no longer required"));
            }
            // Parameters are inputs → diff their schema on the REQUEST side.
            diffSchema(o.getSchema(), n.getSchema(), Side.REQUEST, endpoint, pointer, name, out, newVisited(), 0);
        }
    }

    // ---------------------------------------------------------------- request body

    private void diffRequestBody(String endpoint, RequestBody oldBody, RequestBody newBody, List<Change> out) {
        Schema<?> oldSchema = firstSchema(oldBody != null ? oldBody.getContent() : null);
        Schema<?> newSchema = firstSchema(newBody != null ? newBody.getContent() : null);

        if (oldSchema == null && newSchema != null) {
            boolean required = newBody != null && Boolean.TRUE.equals(newBody.getRequired());
            out.add(Change.of(required ? Classification.BREAKING : Classification.ADDITIVE,
                    required ? ChangeKind.REQUEST_FIELD_ADDED_REQUIRED : ChangeKind.REQUEST_FIELD_ADDED_OPTIONAL,
                    endpoint, "request", null,
                    (required ? "Required" : "Optional") + " request body added"));
            return;
        }
        if (oldSchema != null && newSchema == null) {
            out.add(Change.of(Classification.NON_BREAKING, ChangeKind.REQUEST_FIELD_REMOVED,
                    endpoint, "request", null, "Request body removed"));
            return;
        }
        if (oldSchema != null) {
            diffSchema(oldSchema, newSchema, Side.REQUEST, endpoint, "request", null, out, newVisited(), 0);
        }
    }

    // ---------------------------------------------------------------- responses

    private void diffResponses(String endpoint, ApiResponses oldResponses, ApiResponses newResponses, List<Change> out) {
        Map<String, ApiResponse> oldR = oldResponses != null ? oldResponses : new ApiResponses();
        Map<String, ApiResponse> newR = newResponses != null ? newResponses : new ApiResponses();

        for (String status : union(oldR.keySet(), newR.keySet())) {
            ApiResponse o = oldR.get(status);
            ApiResponse n = newR.get(status);
            String pointer = "response." + status;

            if (o != null && n == null) {
                out.add(Change.of(Classification.BREAKING, ChangeKind.RESPONSE_STATUS_REMOVED,
                        endpoint, pointer, null, "Response status '" + status + "' removed"));
                continue;
            }
            if (o == null && n != null) {
                out.add(Change.of(Classification.ADDITIVE, ChangeKind.RESPONSE_STATUS_ADDED,
                        endpoint, pointer, null, "Response status '" + status + "' added"));
                continue;
            }

            Schema<?> oldSchema = firstSchema(o.getContent());
            Schema<?> newSchema = firstSchema(n.getContent());
            if (oldSchema != null && newSchema != null) {
                diffSchema(oldSchema, newSchema, Side.RESPONSE, endpoint, pointer, null, out, newVisited(), 0);
            } else if (oldSchema != null) {
                out.add(Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                        endpoint, pointer, null, "Response body for '" + status + "' removed"));
            }
        }
    }

    // ---------------------------------------------------------------- security

    private void diffSecurity(String endpoint, List<SecurityRequirement> oldSec,
                              List<SecurityRequirement> newSec, List<Change> out) {
        boolean oldHas = oldSec != null && !oldSec.isEmpty();
        boolean newHas = newSec != null && !newSec.isEmpty();
        if (!oldHas && newHas) {
            out.add(Change.of(Classification.BREAKING, ChangeKind.AUTH_TIGHTENED,
                    endpoint, "security", null, "Authentication is now required for '" + endpoint + "'"));
        } else if (oldHas && !newHas) {
            out.add(Change.of(Classification.NON_BREAKING, ChangeKind.AUTH_RELAXED,
                    endpoint, "security", null, "Authentication is no longer required for '" + endpoint + "'"));
        }
    }

    // ---------------------------------------------------------------- schema recursion

    private void diffSchema(Schema<?> oldS, Schema<?> newS, Side side, String endpoint,
                            String pointer, String field, List<Change> out,
                            Set<Long> visited, int depth) {
        if (oldS == null || newS == null || depth > MAX_DEPTH) {
            return;
        }
        long fingerprint = ((long) System.identityHashCode(oldS) << 32) ^ System.identityHashCode(newS);
        if (!visited.add(fingerprint)) {
            return; // cycle guard
        }

        String oldType = typeOf(oldS);
        String newType = typeOf(newS);

        // Composed schemas (oneOf/anyOf/allOf): a structural change of variant count is treated
        // as a type change. When counts match we recurse element-wise.
        if (oldS instanceof ComposedSchema || newS instanceof ComposedSchema) {
            diffComposed(oldS, newS, side, endpoint, pointer, field, out, visited, depth);
            return;
        }

        // Type change (including format narrowing, e.g. int64 -> int32) — breaking on both sides.
        if (oldType != null && newType != null && !oldType.equals(newType)) {
            out.add(Change.of(Classification.BREAKING, ChangeKind.FIELD_TYPE_CHANGED,
                    endpoint, pointer, field,
                    "Type changed from '" + oldType + "' to '" + newType + "'"));
            return;
        }
        if (Objects.equals(oldType, newType) && oldType != null
                && !Objects.equals(oldS.getFormat(), newS.getFormat())) {
            out.add(Change.of(Classification.BREAKING, ChangeKind.FIELD_TYPE_CHANGED,
                    endpoint, pointer, field,
                    "Type format changed from '" + fmt(oldS) + "' to '" + fmt(newS) + "'"));
            return;
        }

        // Nullability — asymmetric.
        boolean oldNullable = Boolean.TRUE.equals(oldS.getNullable());
        boolean newNullable = Boolean.TRUE.equals(newS.getNullable());
        if (side == Side.RESPONSE && !oldNullable && newNullable) {
            out.add(Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_NULLABLE_ADDED,
                    endpoint, pointer, field, "Response value may now be null"));
        } else if (side == Side.REQUEST && oldNullable && !newNullable) {
            out.add(Change.of(Classification.BREAKING, ChangeKind.REQUEST_FIELD_NULLABLE_REMOVED,
                    endpoint, pointer, field, "Request value no longer accepts null"));
        }

        diffEnum(oldS, newS, side, endpoint, pointer, field, out);

        if ("array".equals(oldType) && "array".equals(newType)) {
            diffSchema(oldS.getItems(), newS.getItems(), side, endpoint, pointer + "[]", field, out, visited, depth + 1);
            return;
        }

        // Object properties.
        diffProperties(oldS, newS, side, endpoint, pointer, out, visited, depth);
    }

    private void diffProperties(Schema<?> oldS, Schema<?> newS, Side side, String endpoint,
                                String pointer, List<Change> out, Set<Long> visited, int depth) {
        Map<String, Schema> oldProps = oldS.getProperties() != null ? oldS.getProperties() : Map.of();
        Map<String, Schema> newProps = newS.getProperties() != null ? newS.getProperties() : Map.of();
        if (oldProps.isEmpty() && newProps.isEmpty()) {
            return;
        }
        Set<String> oldRequired = requiredSet(oldS);
        Set<String> newRequired = requiredSet(newS);

        for (String name : union(oldProps.keySet(), newProps.keySet())) {
            Schema<?> o = oldProps.get(name);
            Schema<?> n = newProps.get(name);
            String childPointer = pointer.equals("request") || pointer.startsWith("response")
                    ? pointer + "." + name : pointer + "." + name;

            if (o == null) { // property added
                if (side == Side.REQUEST) {
                    if (newRequired.contains(name)) {
                        out.add(Change.of(Classification.BREAKING, ChangeKind.REQUEST_FIELD_ADDED_REQUIRED,
                                endpoint, childPointer, name, "New required request field '" + name + "'"));
                    } else {
                        out.add(Change.of(Classification.ADDITIVE, ChangeKind.REQUEST_FIELD_ADDED_OPTIONAL,
                                endpoint, childPointer, name, "New optional request field '" + name + "'"));
                    }
                } else {
                    out.add(Change.of(Classification.ADDITIVE, ChangeKind.RESPONSE_FIELD_ADDED,
                            endpoint, childPointer, name, "New response field '" + name + "'"));
                }
                continue;
            }
            if (n == null) { // property removed
                if (side == Side.REQUEST) {
                    out.add(Change.of(Classification.NON_BREAKING, ChangeKind.REQUEST_FIELD_REMOVED,
                            endpoint, childPointer, name, "Request field '" + name + "' removed (server accepts less)"));
                } else {
                    out.add(Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                            endpoint, childPointer, name, "Response field '" + name + "' removed"));
                }
                continue;
            }

            // Present in both: required transitions (request side) + recurse.
            if (side == Side.REQUEST) {
                boolean wasReq = oldRequired.contains(name);
                boolean nowReq = newRequired.contains(name);
                if (!wasReq && nowReq) {
                    out.add(Change.of(Classification.BREAKING, ChangeKind.REQUEST_FIELD_MADE_REQUIRED,
                            endpoint, childPointer, name, "Request field '" + name + "' is now required"));
                } else if (wasReq && !nowReq) {
                    out.add(Change.of(Classification.NON_BREAKING, ChangeKind.REQUEST_FIELD_MADE_OPTIONAL,
                            endpoint, childPointer, name, "Request field '" + name + "' is no longer required"));
                }
            }
            diffSchema(o, n, side, endpoint, childPointer, name, out, visited, depth + 1);
        }
    }

    private void diffComposed(Schema<?> oldS, Schema<?> newS, Side side, String endpoint,
                              String pointer, String field, List<Change> out, Set<Long> visited, int depth) {
        List<Schema> oldMembers = composedMembers(oldS);
        List<Schema> newMembers = composedMembers(newS);
        if (oldMembers.size() != newMembers.size()) {
            out.add(Change.of(Classification.BREAKING, ChangeKind.FIELD_TYPE_CHANGED,
                    endpoint, pointer, field,
                    "Composed schema shape changed (" + oldMembers.size() + " -> " + newMembers.size() + " variants)"));
            return;
        }
        for (int i = 0; i < oldMembers.size(); i++) {
            diffSchema(oldMembers.get(i), newMembers.get(i), side, endpoint, pointer + "{" + i + "}", field, out, visited, depth + 1);
        }
    }

    // ---------------------------------------------------------------- enums

    private void diffEnum(Schema<?> oldS, Schema<?> newS, Side side, String endpoint,
                          String pointer, String field, List<Change> out) {
        List<?> oldEnum = oldS.getEnum();
        List<?> newEnum = newS.getEnum();
        if (oldEnum == null || newEnum == null || (oldEnum.isEmpty() && newEnum.isEmpty())) {
            return;
        }
        Set<String> oldValues = toStringSet(oldEnum);
        Set<String> newValues = toStringSet(newEnum);

        Set<String> removed = new TreeSet<>(oldValues);
        removed.removeAll(newValues);
        Set<String> added = new TreeSet<>(newValues);
        added.removeAll(oldValues);

        if (side == Side.REQUEST) {
            // Server accepts a smaller set → previously-valid inputs now rejected → breaking.
            for (String value : removed) {
                out.add(Change.of(Classification.BREAKING, ChangeKind.REQUEST_ENUM_VALUE_REMOVED,
                        endpoint, pointer, field, "Request enum value '" + value + "' no longer accepted"));
            }
            // Server accepts more → additive.
            for (String value : added) {
                out.add(Change.of(Classification.ADDITIVE, ChangeKind.REQUEST_ENUM_VALUE_ADDED,
                        endpoint, pointer, field, "Request enum now also accepts '" + value + "'"));
            }
        } else {
            // Server may return a new value a strict consumer can't handle → breaking.
            for (String value : added) {
                out.add(Change.of(Classification.BREAKING, ChangeKind.RESPONSE_ENUM_VALUE_ADDED,
                        endpoint, pointer, field, "Response enum may now return '" + value + "'"));
            }
            for (String value : removed) {
                out.add(Change.of(Classification.NON_BREAKING, ChangeKind.RESPONSE_ENUM_VALUE_REMOVED,
                        endpoint, pointer, field, "Response enum no longer returns '" + value + "'"));
            }
        }
    }

    // ---------------------------------------------------------------- helpers

    private static Set<Long> newVisited() {
        return new HashSet<>();
    }

    private static List<SecurityRequirement> effectiveSecurity(Operation op, OpenAPI api) {
        if (op.getSecurity() != null) {
            return op.getSecurity();
        }
        return api.getSecurity();
    }

    private static Map<String, Parameter> indexParams(List<Parameter> params) {
        Map<String, Parameter> map = new LinkedHashMap<>();
        if (params != null) {
            for (Parameter p : params) {
                if (p != null && p.getName() != null) {
                    map.put(p.getIn() + ":" + p.getName(), p);
                }
            }
        }
        return map;
    }

    private static Schema<?> firstSchema(Content content) {
        if (content == null || content.isEmpty()) {
            return null;
        }
        MediaType json = content.get("application/json");
        MediaType chosen = json != null ? json : content.values().iterator().next();
        return chosen != null ? chosen.getSchema() : null;
    }

    private static String typeOf(Schema<?> schema) {
        if (schema == null) {
            return null;
        }
        if (schema.getType() != null) {
            return schema.getType();
        }
        // OpenAPI 3.1 style: types may be in a set; fall back to structural inference.
        if (schema.getTypes() != null && !schema.getTypes().isEmpty()) {
            return schema.getTypes().iterator().next();
        }
        if (schema.getProperties() != null && !schema.getProperties().isEmpty()) {
            return "object";
        }
        if (schema.getItems() != null) {
            return "array";
        }
        return null;
    }

    private static String fmt(Schema<?> schema) {
        return schema.getFormat() == null ? "none" : schema.getFormat();
    }

    private static Set<String> requiredSet(Schema<?> schema) {
        List<String> req = schema.getRequired();
        return req == null ? Set.of() : new HashSet<>(req);
    }

    @SuppressWarnings("unchecked")
    private static List<Schema> composedMembers(Schema<?> schema) {
        if (schema instanceof ComposedSchema c) {
            if (c.getOneOf() != null) return (List<Schema>) (List<?>) c.getOneOf();
            if (c.getAnyOf() != null) return (List<Schema>) (List<?>) c.getAnyOf();
            if (c.getAllOf() != null) return (List<Schema>) (List<?>) c.getAllOf();
        }
        return Collections.emptyList();
    }

    private static Set<String> toStringSet(List<?> values) {
        Set<String> set = new TreeSet<>();
        for (Object v : values) {
            set.add(String.valueOf(v));
        }
        return set;
    }

    private static boolean isRequired(Boolean required) {
        return Boolean.TRUE.equals(required);
    }

    private static <T> TreeSet<T> union(Set<? extends T> a, Set<? extends T> b) {
        TreeSet<T> all = new TreeSet<>();
        all.addAll(a);
        all.addAll(b);
        return all;
    }
}
