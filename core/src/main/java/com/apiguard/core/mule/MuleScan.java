package com.apiguard.core.mule;

import com.apiguard.core.blast.DependencyManifest;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

public record MuleScan(
        String app,
        String groupId,
        String version,
        Owner owner,
        List<InboundEndpoint> endpoints,
        List<String> declaredApis,
        List<OutboundCall> orphanCalls,
        List<ConfigDriftWarning> configDrift) {

    public MuleScan(String app, String groupId, String version, Owner owner,
                    List<InboundEndpoint> endpoints, List<String> declaredApis,
                    List<OutboundCall> orphanCalls) {
        this(app, groupId, version, owner, endpoints, declaredApis, orphanCalls, List.of());
    }

    public record ConfigDriftWarning(String configName, String host, String unresolvedPlaceholder) {
    }

    public record Owner(String ownerTeam, List<String> reviewers, String slackChannel, String sourceRepo) {
        public static Owner empty() {
            return new Owner(null, List.of(), null, null);
        }
    }

    public record InboundEndpoint(String method, String path, List<OutboundCall> calls) {
        public String label() {
            return method + " " + path;
        }
    }

    public record OutboundCall(String api, String method, String path, String configRef, List<String> fields) {
        public OutboundCall(String api, String method, String path, String configRef) {
            this(api, method, path, configRef, List.of());
        }

        public String endpoint() {
            return method + " " + path;
        }

        public OutboundCall withFields(List<String> fields) {
            return new OutboundCall(api, method, path, configRef, fields);
        }
    }

    public List<String> downstreamApis() {
        TreeSet<String> apis = new TreeSet<>(declaredApis);
        allCalls().forEach(c -> apis.add(c.api()));
        return new ArrayList<>(apis);
    }

    public List<OutboundCall> allCalls() {
        List<OutboundCall> all = new ArrayList<>(orphanCalls);
        endpoints.forEach(e -> all.addAll(e.calls()));
        return all;
    }

    public List<String> undeclaredCalls() {
        TreeSet<String> declared = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        declared.addAll(declaredApis);
        TreeSet<String> missing = new TreeSet<>();
        for (OutboundCall c : allCalls()) {
            if (c.api() == null || c.api().isBlank() || c.api().equalsIgnoreCase("unknown")) {
                continue;
            }
            if (!declared.contains(c.api())) {
                missing.add(c.api());
            }
        }
        return new ArrayList<>(missing);
    }

    public DependencyManifest toManifest() {
        DependencyManifest m = new DependencyManifest();
        m.consumer = app;
        m.ownerTeam = owner != null ? owner.ownerTeam() : null;
        m.reviewers = owner != null ? owner.reviewers() : List.of();
        m.slackChannel = owner != null ? owner.slackChannel() : null;
        m.sourceRepo = owner != null ? owner.sourceRepo() : null;

        record Key(String consumerEndpoint, String producerEndpoint) {
        }
        Map<String, Map<Key, java.util.LinkedHashSet<String>>> byApi = new LinkedHashMap<>();
        for (InboundEndpoint ie : endpoints) {
            for (OutboundCall c : ie.calls()) {
                byApi.computeIfAbsent(c.api(), k -> new LinkedHashMap<>())
                        .computeIfAbsent(new Key(ie.label(), c.endpoint()), k -> new java.util.LinkedHashSet<>())
                        .addAll(c.fields());
            }
        }
        for (OutboundCall c : orphanCalls) {
            byApi.computeIfAbsent(c.api(), k -> new LinkedHashMap<>())
                    .computeIfAbsent(new Key(null, c.endpoint()), k -> new java.util.LinkedHashSet<>())
                    .addAll(c.fields());
        }

        List<DependencyManifest.ApiDependency> deps = new ArrayList<>();
        byApi.forEach((api, byKey) -> {
            DependencyManifest.ApiDependency dep = new DependencyManifest.ApiDependency();
            dep.api = api;
            dep.endpoints = new ArrayList<>();
            byKey.forEach((key, fields) -> {
                DependencyManifest.EndpointDependency ed = new DependencyManifest.EndpointDependency();
                ed.path = key.producerEndpoint();
                ed.consumerEndpoint = key.consumerEndpoint();

                ed.fields = new ArrayList<>(fields);
                dep.endpoints.add(ed);
            });
            deps.add(dep);
        });
        m.dependsOn = deps;
        return m;
    }
}
