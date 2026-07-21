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
@Table(name = "changelog_entry")
public class ChangelogEntryEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "api_id")
    private ApiEntity api;

    @ManyToOne
    @JoinColumn(name = "to_version_id")
    private SpecVersionEntity toVersion;

    @Column(name = "version_label")
    private String versionLabel;

    @Column(name = "markdown", columnDefinition = "text", nullable = false)
    private String markdown;

    @Column(name = "published_at", nullable = false)
    private Instant publishedAt = Instant.now();

    protected ChangelogEntryEntity() {
    }

    public ChangelogEntryEntity(ApiEntity api, SpecVersionEntity toVersion, String versionLabel, String markdown) {
        this.api = api;
        this.toVersion = toVersion;
        this.versionLabel = versionLabel;
        this.markdown = markdown;
    }

    public Long getId() {
        return id;
    }

    public String getVersionLabel() {
        return versionLabel;
    }

    public String getMarkdown() {
        return markdown;
    }

    public Instant getPublishedAt() {
        return publishedAt;
    }

    public ApiEntity getApi() {
        return api;
    }
}
