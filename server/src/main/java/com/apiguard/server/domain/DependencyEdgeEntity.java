package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "dependency_edge")
public class DependencyEdgeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "manifest_id")
    private DependencyManifestEntity manifest;

    @Column(name = "api_name", nullable = false)
    private String apiName;

    @Column(nullable = false)
    private String endpoint;

    private String field;

    @Column(name = "consumer_endpoint")
    private String consumerEndpoint;

    protected DependencyEdgeEntity() {
    }

    public DependencyEdgeEntity(DependencyManifestEntity manifest, String apiName, String endpoint,
                                String field, String consumerEndpoint) {
        this.manifest = manifest;
        this.apiName = apiName;
        this.endpoint = endpoint;
        this.field = field;
        this.consumerEndpoint = consumerEndpoint;
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

    public String getConsumerEndpoint() {
        return consumerEndpoint;
    }
}
