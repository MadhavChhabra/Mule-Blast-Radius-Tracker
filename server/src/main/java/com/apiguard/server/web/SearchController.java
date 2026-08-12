package com.apiguard.server.web;

import com.apiguard.server.domain.DependencyEdgeEntity;
import com.apiguard.server.domain.DependencyManifestEntity;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.service.ManifestService;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/search")
public class SearchController {

    private static final int LIMIT_PER_KIND = 20;

    private final ApiRepository apis;
    private final ManifestService manifests;

    public SearchController(ApiRepository apis, ManifestService manifests) {
        this.apis = apis;
        this.manifests = manifests;
    }

    public record ApiHit(String api) {}
    public record EndpointHit(String api, String endpoint) {}
    public record FieldHit(String api, String endpoint, String field) {}

    public record SearchResults(List<ApiHit> apis, List<EndpointHit> endpoints, List<FieldHit> fields) {}

    static List<ApiHit> rankedApiHits(Set<String> apiNames, String needle) {
        List<String> matches = new ArrayList<>();
        for (String name : apiNames) {
            if (needle.isEmpty() || name.toLowerCase(Locale.ROOT).contains(needle)) {
                matches.add(name);
            }
        }
        matches.sort((a, b) -> {
            int byRank = Integer.compare(rank(a, needle), rank(b, needle));
            return byRank != 0 ? byRank : a.compareToIgnoreCase(b);
        });
        List<ApiHit> hits = new ArrayList<>();
        for (String name : matches.subList(0, Math.min(LIMIT_PER_KIND, matches.size()))) {
            hits.add(new ApiHit(name));
        }
        return hits;
    }

    private static int rank(String name, String needle) {
        if (needle.isEmpty()) return 0;
        String lower = name.toLowerCase(Locale.ROOT);
        if (lower.equals(needle)) return 0;
        if (lower.startsWith(needle)) return 1;
        int at = lower.indexOf('-' + needle);
        if (at >= 0) return 2;
        return 3;
    }

    @GetMapping
    @Transactional(readOnly = true)
    public SearchResults search(@RequestParam(defaultValue = "") String q) {
        String needle = q == null ? "" : q.trim().toLowerCase(Locale.ROOT);

        Set<String> apiNames = new LinkedHashSet<>();
        apis.findAll().forEach(a -> apiNames.add(a.getName()));
        List<DependencyManifestEntity> manifestList = manifests.all();
        for (DependencyManifestEntity m : manifestList) {
            if (m.getConsumer() != null) apiNames.add(m.getConsumer());
            for (DependencyEdgeEntity e : m.getEdges()) {
                if (e.getApiName() != null) apiNames.add(e.getApiName());
            }
        }

        List<ApiHit> apiHits = rankedApiHits(apiNames, needle);

        Map<String, EndpointHit> endpointDedup = new LinkedHashMap<>();
        Map<String, FieldHit> fieldDedup = new LinkedHashMap<>();
        for (DependencyManifestEntity m : manifestList) {
            for (DependencyEdgeEntity e : m.getEdges()) {
                String api = e.getApiName();
                String endpoint = e.getEndpoint();
                String field = e.getField();
                if (api == null || endpoint == null) continue;
                String epKey = api.toLowerCase(Locale.ROOT) + "|" + endpoint.toLowerCase(Locale.ROOT);
                if (needle.isEmpty()
                        || endpoint.toLowerCase(Locale.ROOT).contains(needle)
                        || api.toLowerCase(Locale.ROOT).contains(needle)) {
                    endpointDedup.putIfAbsent(epKey, new EndpointHit(api, endpoint));
                }
                if (field != null && !field.isBlank() && !"*".equals(field)) {
                    String fKey = epKey + "|" + field.toLowerCase(Locale.ROOT);
                    if (needle.isEmpty() || field.toLowerCase(Locale.ROOT).contains(needle)) {
                        fieldDedup.putIfAbsent(fKey, new FieldHit(api, endpoint, field));
                    }
                }
                if (endpointDedup.size() >= LIMIT_PER_KIND && fieldDedup.size() >= LIMIT_PER_KIND) break;
            }
        }

        return new SearchResults(new ArrayList<>(apiHits),
                new ArrayList<>(endpointDedup.values()).subList(0,
                        Math.min(LIMIT_PER_KIND, endpointDedup.size())),
                new ArrayList<>(fieldDedup.values()).subList(0,
                        Math.min(LIMIT_PER_KIND, fieldDedup.size())));
    }
}
