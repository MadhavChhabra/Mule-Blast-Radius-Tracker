package com.apiguard.server.domain;

import jakarta.persistence.CascadeType;
import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "dependency_manifest")
public class DependencyManifestEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false, unique = true)
    private String consumer;

    @Column(name = "owner_team")
    private String ownerTeam;

    @Column(name = "slack_channel")
    private String slackChannel;

    @Column(name = "source_repo")
    private String sourceRepo;

    @ElementCollection
    @CollectionTable(name = "dependency_manifest_reviewer", joinColumns = @JoinColumn(name = "manifest_id"))
    @Column(name = "reviewer")
    private List<String> reviewers = new ArrayList<>();

    @OneToMany(mappedBy = "manifest", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<DependencyEdgeEntity> edges = new ArrayList<>();

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt = Instant.now();

    protected DependencyManifestEntity() {
    }

    public DependencyManifestEntity(String consumer, String ownerTeam, String slackChannel, String sourceRepo) {
        this.consumer = consumer;
        this.ownerTeam = ownerTeam;
        this.slackChannel = slackChannel;
        this.sourceRepo = sourceRepo;
    }

    public void addEdge(String apiName, String endpoint, String field, String consumerEndpoint) {
        edges.add(new DependencyEdgeEntity(this, apiName, endpoint, field, consumerEndpoint));
    }

    public void clearEdges() {
        edges.clear();
    }

    public void setReviewers(List<String> reviewers) {
        this.reviewers = reviewers == null ? new ArrayList<>() : new ArrayList<>(reviewers);
    }

    public void setOwnerTeam(String ownerTeam) {
        this.ownerTeam = ownerTeam;
    }

    public void setSlackChannel(String slackChannel) {
        this.slackChannel = slackChannel;
    }

    public void setSourceRepo(String sourceRepo) {
        this.sourceRepo = sourceRepo;
    }

    public void touch() {
        this.updatedAt = Instant.now();
    }

    public Long getId() {
        return id;
    }

    public String getConsumer() {
        return consumer;
    }

    public String getOwnerTeam() {
        return ownerTeam;
    }

    public String getSlackChannel() {
        return slackChannel;
    }

    public String getSourceRepo() {
        return sourceRepo;
    }

    public List<String> getReviewers() {
        return reviewers;
    }

    public List<DependencyEdgeEntity> getEdges() {
        return edges;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }
}
