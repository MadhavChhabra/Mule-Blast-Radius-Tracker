package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "blast_result")
public class BlastResultEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "pr_ref")
    private String prRef;

    @Column(name = "change_id")
    private Long changeId;

    private String consumer;

    @Column(name = "notified_at")
    private Instant notifiedAt;

    protected BlastResultEntity() {
    }

    public BlastResultEntity(String prRef, Long changeId, String consumer, Instant notifiedAt) {
        this.prRef = prRef;
        this.changeId = changeId;
        this.consumer = consumer;
        this.notifiedAt = notifiedAt;
    }

    public Long getId() {
        return id;
    }

    public String getConsumer() {
        return consumer;
    }
}
