package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "anypoint_credential")
public class AnypointCredentialEntity {

    @Id
    private Integer id;

    @Column(name = "client_id", length = 512)
    private String clientId;

    @Column(name = "client_secret", length = 4096)
    private String clientSecret;

    @Column(name = "org_id", length = 256)
    private String orgId;

    @Column(length = 256)
    private String environment;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    protected AnypointCredentialEntity() {
    }

    public AnypointCredentialEntity(Integer id) {
        this.id = id;
    }

    public Integer getId() {
        return id;
    }

    public String getClientId() {
        return clientId;
    }

    public void setClientId(String clientId) {
        this.clientId = clientId;
    }

    public String getClientSecret() {
        return clientSecret;
    }

    public void setClientSecret(String clientSecret) {
        this.clientSecret = clientSecret;
    }

    public String getOrgId() {
        return orgId;
    }

    public void setOrgId(String orgId) {
        this.orgId = orgId;
    }

    public String getEnvironment() {
        return environment;
    }

    public void setEnvironment(String environment) {
        this.environment = environment;
    }

    public void setUpdatedAt(Instant updatedAt) {
        this.updatedAt = updatedAt;
    }
}
