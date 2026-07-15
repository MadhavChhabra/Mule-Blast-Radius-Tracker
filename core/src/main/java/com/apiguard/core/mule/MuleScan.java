package com.apiguard.core.mule;

import com.apiguard.core.blast.DependencyManifest;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

/**
 * The result of scanning one Mule application project — the auto-discovered dependency picture,
 * built from {@code pom.xml} (Exchange dependencies) and the flow XML ({@code <http:request>}
 * calls under APIkit endpoint flows). No hand-written manifest required.
 *
 * @param app            the Mule app / API name (the {@code artifactId})
 * @param groupId        Exchange org id (the {@code groupId})
 * @param version        the app version
 * @param endpoints      the app's own inbound endpoints, each with the downstream calls it makes
 * @param declaredApis   downstream API assets declared in {@code pom.xml} (the aggregate view)
 * @param orphanCalls    downstream calls found outside a recognizable endpoint flow (sub-flows)
 */
public record MuleScan(
        String app,
        String groupId,
        String version,
        Owner owner,
        List<InboundEndpoint> endpoints,
        List<String> declaredApis,
        List<OutboundCall> orphanCalls) {

    /** Optional ownership metadata (from an {@code apiguard-owner.yaml}) so blast radius is actionable. */
    public record Owner(String ownerTeam, List<String> reviewers, String slackChannel, String sourceRepo) {
        public static Owner empty() {
            return new Owner(null, List.of(), null, null);
        }
    }

    /** One inbound endpoint the app exposes (from an APIkit flow), and what it calls downstream. */
    public record InboundEndpoint(String method, String path, List<OutboundCall> calls) {
        public String label() {
            return method + " " + path;
        }
    }

    /**
     * One downstream call the app makes (an {@code <http:request>}). {@code fields} are the
     * downstream response fields the surrounding flow reads via DataWeave ({@code payload.x}) —
     * empty when no field lineage was found (then the dependency is endpoint-level).
     */
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

    /** Every distinct downstream API this app touches (declared in pom ∪ actually called). */
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

    /**
     * Convert this scan into a consumer {@link DependencyManifest} — so the existing
     * {@code BlastRadiusResolver}, dashboard graph and Explorer work with zero changes.
     * The Mule app becomes a <i>consumer</i> of the downstream APIs it calls.
     */
    public DependencyManifest toManifest() {
        DependencyManifest m = new DependencyManifest();
        m.consumer = app;
        m.ownerTeam = owner != null ? owner.ownerTeam() : null;
        m.reviewers = owner != null ? owner.reviewers() : List.of();
        m.slackChannel = owner != null ? owner.slackChannel() : null;
        m.sourceRepo = owner != null ? owner.sourceRepo() : null;

        // Group outbound calls keyed by (producer api, this app's inbound endpoint, producer endpoint)
        // so the per-endpoint picture survives: we remember which of *our* endpoints made each call.
        // Key = consumerEndpoint (null for sub-flow / app-level) + producer endpoint.
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
                // Field-level when DataWeave lineage was found; endpoint-level (empty) otherwise.
                ed.fields = new ArrayList<>(fields);
                dep.endpoints.add(ed);
            });
            deps.add(dep);
        });
        m.dependsOn = deps;
        return m;
    }
}
