package com.apiguard.server.domain;

import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.ChangeKind;
import com.apiguard.core.diff.Classification;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "change_record")
public class ChangeRecordEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "api_id")
    private ApiEntity api;

    @ManyToOne
    @JoinColumn(name = "from_version_id")
    private SpecVersionEntity fromVersion;

    @ManyToOne
    @JoinColumn(name = "to_version_id")
    private SpecVersionEntity toVersion;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Classification classification;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private ChangeKind kind;

    private String endpoint;

    @Column(name = "json_pointer")
    private String jsonPointer;

    private String field;

    private String description;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt = Instant.now();

    protected ChangeRecordEntity() {
    }

    public ChangeRecordEntity(ApiEntity api, SpecVersionEntity from, SpecVersionEntity to, Change change) {
        this.api = api;
        this.fromVersion = from;
        this.toVersion = to;
        this.classification = change.classification();
        this.kind = change.kind();
        this.endpoint = change.endpoint();
        this.jsonPointer = change.jsonPointer();
        this.field = change.field();
        this.description = change.description();
    }

    public Change toChange() {
        return Change.of(classification, kind, endpoint, jsonPointer, field, description);
    }

    public Long getId() {
        return id;
    }

    public Classification getClassification() {
        return classification;
    }

    public ChangeKind getKind() {
        return kind;
    }

    public String getEndpoint() {
        return endpoint;
    }

    public String getField() {
        return field;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
