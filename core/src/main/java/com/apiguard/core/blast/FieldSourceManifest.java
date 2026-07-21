package com.apiguard.core.blast;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public class FieldSourceManifest {

    public String api;
    public List<Source> sources = List.of();

    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class Source {

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
