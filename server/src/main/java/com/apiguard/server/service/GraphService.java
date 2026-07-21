package com.apiguard.server.service;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.catalog.ApiLayer;
import com.apiguard.core.diff.Change;
import com.apiguard.server.domain.ApiEntity;
import com.apiguard.server.domain.ChangeRecordEntity;
import com.apiguard.server.domain.DependencyEdgeEntity;
import com.apiguard.server.domain.DependencyManifestEntity;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.repo.ChangeRepository;
import com.apiguard.server.web.Dtos;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class GraphService {

    private final ManifestService manifestService;
    private final ApiRepository apis;
    private final ChangeRepository changes;

    public GraphService(ManifestService manifestService, ApiRepository apis, ChangeRepository changes) {
        this.manifestService = manifestService;
        this.apis = apis;
        this.changes = changes;
    }

    @Transactional(readOnly = true)
    public Dtos.GraphDto build() {
        List<DependencyManifestEntity> manifests = manifestService.all();
        BlastRadiusResolver resolver = manifestService.buildResolver();

        record Edge(String from, String to) {
        }
        Map<Edge, Map<String, LinkedHashSet<String>>> viaMap = new LinkedHashMap<>();
        Set<String> names = new LinkedHashSet<>();
        Map<String, String> ownerByName = new HashMap<>();
        Map<String, List<String>> reviewersByName = new HashMap<>();

        for (DependencyManifestEntity m : manifests) {
            names.add(m.getConsumer());
            if (m.getOwnerTeam() != null) {
                ownerByName.put(m.getConsumer(), m.getOwnerTeam());
            }
            if (m.getReviewers() != null && !m.getReviewers().isEmpty()) {
                reviewersByName.put(m.getConsumer(), List.copyOf(m.getReviewers()));
            }
            for (DependencyEdgeEntity e : m.getEdges()) {
                names.add(e.getApiName());
                Edge key = new Edge(m.getConsumer(), e.getApiName());
                String endpoint = e.getEndpoint() == null ? "*" : e.getEndpoint();
                LinkedHashSet<String> fields = viaMap
                        .computeIfAbsent(key, k -> new LinkedHashMap<>())
                        .computeIfAbsent(endpoint, k -> new LinkedHashSet<>());
                if (e.getField() != null) {
                    fields.add(e.getField());
                }
            }
        }
        Set<Edge> rawEdges = viaMap.keySet();

        Map<String, String> labelByName = new HashMap<>();
        for (ApiEntity api : apis.findAll()) {
            names.add(api.getName());
            if (api.getDisplayName() != null && !api.getDisplayName().isBlank()) {
                labelByName.put(api.getName(), api.getDisplayName());
            }
        }

        Map<String, Integer> inDeg = new HashMap<>();
        Map<String, Integer> outDeg = new HashMap<>();
        for (Edge e : rawEdges) {
            outDeg.merge(e.from(), 1, Integer::sum);
            inDeg.merge(e.to(), 1, Integer::sum);
        }
        Set<String> registered = new LinkedHashSet<>();
        apis.findAll().forEach(a -> registered.add(a.getName()));

        Map<String, Dtos.GraphNode> nodes = new LinkedHashMap<>();
        for (String name : names) {
            int in = inDeg.getOrDefault(name, 0);
            int out = outDeg.getOrDefault(name, 0);
            boolean provider = in > 0 || registered.contains(name);
            ApiLayer layer = ApiLayer.classify(name);
            if (layer == ApiLayer.UNKNOWN) {
                layer = provider ? ApiLayer.UNKNOWN : ApiLayer.APP;
            }
            boolean isApi = provider || layer.isApi();
            nodes.put(name, new Dtos.GraphNode(name, labelByName.getOrDefault(name, name), layer.name(), isApi, out, in,
                    ownerByName.get(name), reviewersByName.getOrDefault(name, List.of())));
        }

        Map<String, Set<String>> brokenConsumersByProvider = new HashMap<>();
        for (Edge e : rawEdges) {

            if (!brokenConsumersByProvider.containsKey(e.to())) {
                brokenConsumersByProvider.put(e.to(), brokenConsumers(resolver, e.to()));
            }
        }
        List<Dtos.GraphEdge> edges = new ArrayList<>();
        for (Edge e : rawEdges) {
            List<String> via = new ArrayList<>();
            viaMap.get(e).forEach((endpoint, fields) -> {
                String label = endpoint.equals("*") ? "whole API" : endpoint;
                if (!fields.isEmpty()) {
                    label += " · " + String.join(", ", fields);
                }
                via.add(label);
            });
            Set<String> broken = brokenConsumersByProvider.get(e.to());
            String risk = broken == null ? "none" : (broken.contains(e.from()) ? "breaking" : "safe");
            edges.add(new Dtos.GraphEdge(e.from(), e.to(), "depends on", risk, via));
        }

        return new Dtos.GraphDto(new ArrayList<>(nodes.values()), edges);
    }

    private Set<String> brokenConsumers(BlastRadiusResolver resolver, String apiName) {
        List<ChangeRecordEntity> recent = changes.findByApi_NameOrderByIdDesc(apiName);
        if (recent.isEmpty()) {
            return null;
        }
        List<Change> asChanges = recent.stream().limit(200).map(ChangeRecordEntity::toChange).toList();
        Set<String> broken = new java.util.HashSet<>();
        for (BlastRadiusResolver.Impact impact : resolver.resolve(apiName, asChanges)) {
            if (impact.change().isBreaking()) {
                impact.downstream().forEach(c -> broken.add(c.consumer()));
            }
        }
        return broken;
    }
}
