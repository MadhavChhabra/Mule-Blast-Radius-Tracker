package com.apiguard.core.diff;

/**
 * The specific kind of change detected between two OpenAPI specs.
 *
 * <p>Each kind carries a <i>default</i> classification, but the {@link DiffEngine}
 * always sets the classification explicitly on the {@link Change} because a few
 * kinds are context-dependent (e.g. a removed parameter is only breaking when it
 * was required). The default here is used for documentation and changelog grouping.
 */
public enum ChangeKind {
    // ---- Endpoints / operations ----
    ENDPOINT_REMOVED("Endpoint removed", Classification.BREAKING),
    OPERATION_REMOVED("Operation removed", Classification.BREAKING),
    ENDPOINT_ADDED("Endpoint added", Classification.ADDITIVE),
    OPERATION_ADDED("Operation added", Classification.ADDITIVE),

    // ---- Parameters ----
    PARAM_REMOVED("Parameter removed", Classification.BREAKING),
    PARAM_ADDED_REQUIRED("Required parameter added", Classification.BREAKING),
    PARAM_ADDED_OPTIONAL("Optional parameter added", Classification.ADDITIVE),
    PARAM_MADE_REQUIRED("Parameter made required", Classification.BREAKING),
    PARAM_MADE_OPTIONAL("Parameter made optional", Classification.NON_BREAKING),

    // ---- Request body fields ----
    REQUEST_FIELD_ADDED_REQUIRED("Required request field added", Classification.BREAKING),
    REQUEST_FIELD_ADDED_OPTIONAL("Optional request field added", Classification.ADDITIVE),
    REQUEST_FIELD_REMOVED("Request field removed", Classification.NON_BREAKING),
    REQUEST_FIELD_MADE_REQUIRED("Request field made required", Classification.BREAKING),
    REQUEST_FIELD_MADE_OPTIONAL("Request field made optional", Classification.NON_BREAKING),

    // ---- Response body fields ----
    RESPONSE_FIELD_ADDED("Response field added", Classification.ADDITIVE),
    RESPONSE_FIELD_REMOVED("Response field removed", Classification.BREAKING),

    // ---- Types / nullability (either side) ----
    FIELD_TYPE_CHANGED("Field type changed", Classification.BREAKING),
    RESPONSE_FIELD_NULLABLE_ADDED("Response field became nullable", Classification.BREAKING),
    REQUEST_FIELD_NULLABLE_REMOVED("Request field no longer accepts null", Classification.BREAKING),

    // ---- Enums (request/response asymmetry) ----
    REQUEST_ENUM_VALUE_REMOVED("Request enum value removed", Classification.BREAKING),
    REQUEST_ENUM_VALUE_ADDED("Request enum value added", Classification.ADDITIVE),
    RESPONSE_ENUM_VALUE_ADDED("Response enum value added", Classification.BREAKING),
    RESPONSE_ENUM_VALUE_REMOVED("Response enum value removed", Classification.NON_BREAKING),

    // ---- Security ----
    AUTH_TIGHTENED("Auth requirement added or tightened", Classification.BREAKING),
    AUTH_RELAXED("Auth requirement relaxed", Classification.NON_BREAKING),

    // ---- Response status codes ----
    RESPONSE_STATUS_ADDED("Response status code added", Classification.ADDITIVE),
    RESPONSE_STATUS_REMOVED("Response status code removed", Classification.BREAKING),

    // ---- Docs ----
    DOC_CHANGED("Documentation changed", Classification.NON_BREAKING);

    private final String label;
    private final Classification defaultClassification;

    ChangeKind(String label, Classification defaultClassification) {
        this.label = label;
        this.defaultClassification = defaultClassification;
    }

    public String label() {
        return label;
    }

    public Classification defaultClassification() {
        return defaultClassification;
    }
}
