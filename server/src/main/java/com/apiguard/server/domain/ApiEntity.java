package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "api")
public class ApiEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String name;

    private String repo;

    @Column(name = "spec_path")
    private String specPath;

    @Column(name = "display_name")
    private String displayName;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected ApiEntity() {
    }

    public ApiEntity(String name, String repo, String specPath) {
        this(name, repo, specPath, null);
    }

    public ApiEntity(String name, String repo, String specPath, String displayName) {
        this.name = name;
        this.repo = repo;
        this.specPath = specPath;
        this.displayName = displayName;
    }

    public Long getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public String getRepo() {
        return repo;
    }

    public String getSpecPath() {
        return specPath;
    }

    public String getDisplayName() {
        return displayName;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
