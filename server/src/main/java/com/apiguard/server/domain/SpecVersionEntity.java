package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "spec_version")
public class SpecVersionEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(optional = false)
    @JoinColumn(name = "api_id")
    private ApiEntity api;

    @Column(name = "git_sha")
    private String gitSha;

    @Column(name = "version_label")
    private String versionLabel;

    @Column(name = "raw_spec", columnDefinition = "text")
    private String rawSpec;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected SpecVersionEntity() {
    }

    public SpecVersionEntity(ApiEntity api, String gitSha, String versionLabel, String rawSpec) {
        this.api = api;
        this.gitSha = gitSha;
        this.versionLabel = versionLabel;
        this.rawSpec = rawSpec;
    }

    public Long getId() {
        return id;
    }

    public ApiEntity getApi() {
        return api;
    }

    public String getVersionLabel() {
        return versionLabel;
    }

    public String getRawSpec() {
        return rawSpec;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
