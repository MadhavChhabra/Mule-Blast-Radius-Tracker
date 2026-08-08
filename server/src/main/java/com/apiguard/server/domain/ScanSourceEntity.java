package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "scan_source")
public class ScanSourceEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true, length = 1024)
    private String url;

    /// Encrypted userinfo (a PAT / app password) for a private repo. Never leaves the server:
    /// it is re-attached to the URL only when cloning or listing an org.
    @Column(length = 2048)
    private String credential;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected ScanSourceEntity() {
    }

    public ScanSourceEntity(String url) {
        this.url = url;
    }

    public ScanSourceEntity(String url, String credential) {
        this.url = url;
        this.credential = credential;
    }

    public Long getId() {
        return id;
    }

    public String getUrl() {
        return url;
    }

    public void setUrl(String url) {
        this.url = url;
    }

    public String getCredential() {
        return credential;
    }

    public void setCredential(String credential) {
        this.credential = credential;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
