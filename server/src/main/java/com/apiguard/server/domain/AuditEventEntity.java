package com.apiguard.server.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;

@Entity
@Table(name = "audit_event")
public class AuditEventEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Instant ts = Instant.now();

    private String actor;

    @Column(nullable = false, length = 64)
    private String action;

    @Column(length = 512)
    private String subject;

    @Column(length = 2048)
    private String detail;

    protected AuditEventEntity() {
    }

    public AuditEventEntity(String actor, String action, String subject, String detail) {
        this.actor = actor;
        this.action = action;
        this.subject = subject;
        this.detail = detail;
    }

    public Long getId() { return id; }
    public Instant getTs() { return ts; }
    public String getActor() { return actor; }
    public String getAction() { return action; }
    public String getSubject() { return subject; }
    public String getDetail() { return detail; }
}
