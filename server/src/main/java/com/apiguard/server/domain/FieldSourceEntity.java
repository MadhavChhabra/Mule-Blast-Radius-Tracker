package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "field_source")
public class FieldSourceEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "api_name", nullable = false)
    private String apiName;

    @Column(nullable = false)
    private String endpoint;

    @Column(nullable = false)
    private String field;

    @Column(name = "upstream_api")
    private String upstreamApi;

    @Column(name = "upstream_endpoint")
    private String upstreamEndpoint;

    @Column(name = "upstream_field")
    private String upstreamField;

    protected FieldSourceEntity() {
    }

    public FieldSourceEntity(String apiName, String endpoint, String field,
                             String upstreamApi, String upstreamEndpoint, String upstreamField) {
        this.apiName = apiName;
        this.endpoint = endpoint;
        this.field = field;
        this.upstreamApi = upstreamApi;
        this.upstreamEndpoint = upstreamEndpoint;
        this.upstreamField = upstreamField;
    }

    public String getApiName() {
        return apiName;
    }

    public String getEndpoint() {
        return endpoint;
    }

    public String getField() {
        return field;
    }

    public String getUpstreamApi() {
        return upstreamApi;
    }

    public String getUpstreamEndpoint() {
        return upstreamEndpoint;
    }

    public String getUpstreamField() {
        return upstreamField;
    }
}
