package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "repo_revision")
public class RepoRevisionEntity {

    @Id
    @Column(name = "url_key", length = 1024)
    private String urlKey;

    @Column(name = "commit_sha", nullable = false, length = 64)
    private String commitSha;

    @Column(name = "scanned_at", nullable = false)
    private Instant scannedAt = Instant.now();

    protected RepoRevisionEntity() {
    }

    public RepoRevisionEntity(String urlKey, String commitSha) {
        this.urlKey = urlKey;
        this.commitSha = commitSha;
    }

    public String getUrlKey() {
        return urlKey;
    }

    public String getCommitSha() {
        return commitSha;
    }

    public void update(String commitSha) {
        this.commitSha = commitSha;
        this.scannedAt = Instant.now();
    }

    public Instant getScannedAt() {
        return scannedAt;
    }
}
