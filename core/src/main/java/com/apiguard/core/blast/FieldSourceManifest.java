package com.apiguard.core.blast;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.util.List;

/**
 * Optional <b>upstream lineage</b>, declared by a producer in its own repo, so blast radius can
 * be traced two ways: where a field is consumed (downstream) <i>and</i> where it is sourced from
 * (upstream).
 *
 * <pre>
 * api: payments-api
 * sources:
 *   - endpoint: "GET /payments/{id}"
 *     field: "customerId"
 *     from: { api: customers-api, endpoint: "GET /customers/{id}", field: "id" }
 * </pre>
 */
@JsonIgnoreProperties(ignoreUnknown = true)
public class FieldSourceManifest {

    public String api;
    public List<Source> sources = List.of();

    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Source {
        /** e.g. {@code "GET /payments/{id}"} */
        public String endpoint;
        public String field;
        public From from;
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class From {
        public String api;
        public String endpoint;
        public String field;
    }
}
