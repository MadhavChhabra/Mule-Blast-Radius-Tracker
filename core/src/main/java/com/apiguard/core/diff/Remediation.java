package com.apiguard.core.diff;

public final class Remediation {

    private Remediation() {
    }

    public static String forChange(Change change) {
        if (change == null || !change.isBreaking()) {
            return null;
        }
        return forKind(change.kind());
    }

    public static String forKind(ChangeKind kind) {
        return switch (kind) {
            case ENDPOINT_REMOVED, OPERATION_REMOVED ->
                    "Add the replacement alongside the old one, mark the old as deprecated, and remove it "
                            + "only in a new major version once callers have moved.";
            case PARAM_REMOVED ->
                    "Keep accepting this parameter until every caller stops sending it; drop it only in a "
                            + "new major version.";
            case PARAM_ADDED_REQUIRED, REQUEST_FIELD_ADDED_REQUIRED ->
                    "Make it optional with a sensible default instead of required, so today's callers keep "
                            + "working. Require it only in a new major version.";
            case PARAM_MADE_REQUIRED, REQUEST_FIELD_MADE_REQUIRED ->
                    "Keep it optional and apply a default when it is missing; require it only in a new "
                            + "major version.";
            case RESPONSE_FIELD_REMOVED ->
                    "Keep returning the field, mark it deprecated in the spec, and remove it only in a new "
                            + "major version once consumers stop reading it.";
            case FIELD_TYPE_CHANGED ->
                    "A type change breaks every consumer that parses this value. Add a new field with the "
                            + "new type and keep the old one, or version the endpoint (e.g. /v2).";
            case RESPONSE_FIELD_NULLABLE_ADDED ->
                    "Consumers may not handle null. Keep returning a non-null value (a default or empty), "
                            + "or version the endpoint.";
            case REQUEST_FIELD_NULLABLE_REMOVED ->
                    "Callers may still send null. Keep accepting it (treat null as absent), or version the "
                            + "endpoint.";
            case REQUEST_ENUM_VALUE_REMOVED ->
                    "Callers still sending the old value will be rejected. Keep accepting it (map it to a "
                            + "supported value), or coordinate the removal with every sender first.";
            case RESPONSE_ENUM_VALUE_ADDED ->
                    "Consumers with strict validation may reject the new value. Announce it before release, "
                            + "or version the endpoint so only new consumers receive it.";
            case RESPONSE_STATUS_REMOVED ->
                    "Some consumers may branch on this status. Keep returning it, or confirm nobody handles "
                            + "it before removing.";
            case AUTH_TIGHTENED ->
                    "Existing callers will start getting 401/403. Notify consumers, accept both old and new "
                            + "auth during a grace period, then enforce.";
            default ->
                    "Release this behind a new major version and give consumers time to migrate.";
        };
    }
}
