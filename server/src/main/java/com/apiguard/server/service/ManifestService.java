package com.apiguard.server.service;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.blast.DependencyManifest;
import com.apiguard.core.blast.FieldSourceManifest;
import com.apiguard.server.domain.DependencyEdgeEntity;
import com.apiguard.server.domain.DependencyManifestEntity;
import com.apiguard.server.domain.FieldSourceEntity;
import com.apiguard.server.repo.DependencyManifestRepository;
import com.apiguard.server.repo.FieldSourceRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class ManifestService {

    private final DependencyManifestRepository manifests;
    private final FieldSourceRepository fieldSources;

    public ManifestService(DependencyManifestRepository manifests, FieldSourceRepository fieldSources) {
        this.manifests = manifests;
        this.fieldSources = fieldSources;
    }

    @Transactional
    public DependencyManifestEntity ingestDependency(DependencyManifest m) {
        DependencyManifestEntity entity = manifests.findByConsumer(m.consumer)
                .orElseGet(() -> new DependencyManifestEntity(m.consumer, m.ownerTeam, m.slackChannel, m.sourceRepo));
        entity.setOwnerTeam(m.ownerTeam);
        entity.setSlackChannel(m.slackChannel);
        entity.setSourceRepo(m.sourceRepo);
        entity.setReviewers(m.reviewers);
        entity.clearEdges();
        if (m.dependsOn != null) {
            for (DependencyManifest.ApiDependency dep : m.dependsOn) {
                if (dep.endpoints == null) {
                    continue;
                }
                for (DependencyManifest.EndpointDependency ep : dep.endpoints) {
                    if (ep.fields == null || ep.fields.isEmpty()) {
                        entity.addEdge(dep.api, ep.path, null, ep.consumerEndpoint);
                    } else {
                        for (String field : ep.fields) {
                            entity.addEdge(dep.api, ep.path, field, ep.consumerEndpoint);
                        }
                    }
                }
            }
        }
        entity.touch();
        return manifests.save(entity);
    }

    @Transactional
    public void ingestSources(FieldSourceManifest m) {
        List<FieldSourceEntity> existing = fieldSources.findAll().stream()
                .filter(f -> f.getApiName().equalsIgnoreCase(m.api))
                .toList();
        fieldSources.deleteAll(existing);
        if (m.sources != null) {
            for (FieldSourceManifest.Source s : m.sources) {
                String upApi = s.from != null ? s.from.api : null;
                String upEndpoint = s.from != null ? s.from.endpoint : null;
                String upField = s.from != null ? s.from.field : null;
                fieldSources.save(new FieldSourceEntity(m.api, s.endpoint, s.field, upApi, upEndpoint, upField));
            }
        }
    }

    @Transactional(readOnly = true)
    public BlastRadiusResolver buildResolver() {
        List<DependencyManifest> consumers = new ArrayList<>();
        for (DependencyManifestEntity e : manifests.findAll()) {
            consumers.add(toCore(e));
        }
        List<FieldSourceManifest> sources = toCoreSources(fieldSources.findAll());
        return new BlastRadiusResolver(consumers, sources);
    }

    public List<DependencyManifestEntity> all() {
        return manifests.findAll();
    }

    @Transactional(readOnly = true)
    private static DependencyManifest toCore(DependencyManifestEntity e) {
        DependencyManifest m = new DependencyManifest();
        m.consumer = e.getConsumer();
        m.ownerTeam = e.getOwnerTeam();
        m.slackChannel = e.getSlackChannel();
        m.sourceRepo = e.getSourceRepo();
        m.reviewers = List.copyOf(e.getReviewers());

        Map<String, Map<String, List<String>>> byApi = new LinkedHashMap<>();
        for (DependencyEdgeEntity edge : e.getEdges()) {
            byApi.computeIfAbsent(edge.getApiName(), k -> new LinkedHashMap<>())
                    .computeIfAbsent(edge.getEndpoint(), k -> new ArrayList<>());
            if (edge.getField() != null) {
                byApi.get(edge.getApiName()).get(edge.getEndpoint()).add(edge.getField());
            }
        }
        List<DependencyManifest.ApiDependency> deps = new ArrayList<>();
        byApi.forEach((api, endpoints) -> {
            DependencyManifest.ApiDependency dep = new DependencyManifest.ApiDependency();
            dep.api = api;
            dep.endpoints = new ArrayList<>();
            endpoints.forEach((path, fields) -> {
                DependencyManifest.EndpointDependency ep = new DependencyManifest.EndpointDependency();
                ep.path = path;
                ep.fields = fields;
                dep.endpoints.add(ep);
            });
            deps.add(dep);
        });
        m.dependsOn = deps;
        return m;
    }

    private static List<FieldSourceManifest> toCoreSources(List<FieldSourceEntity> entities) {
        Map<String, FieldSourceManifest> byApi = new LinkedHashMap<>();
        for (FieldSourceEntity e : entities) {
            FieldSourceManifest m = byApi.computeIfAbsent(e.getApiName(), k -> {
                FieldSourceManifest fm = new FieldSourceManifest();
                fm.api = k;
                fm.sources = new ArrayList<>();
                return fm;
            });
            FieldSourceManifest.Source s = new FieldSourceManifest.Source();
            s.endpoint = e.getEndpoint();
            s.field = e.getField();
            FieldSourceManifest.From from = new FieldSourceManifest.From();
            from.api = e.getUpstreamApi();
            from.endpoint = e.getUpstreamEndpoint();
            from.field = e.getUpstreamField();
            s.from = from;
            m.sources.add(s);
        }
        return new ArrayList<>(byApi.values());
    }
}
