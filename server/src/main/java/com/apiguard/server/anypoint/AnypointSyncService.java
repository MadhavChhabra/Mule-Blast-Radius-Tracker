package com.apiguard.server.anypoint;

import com.apiguard.core.blast.DependencyManifest;
import com.apiguard.server.domain.ApiEntity;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.service.ManifestService;
import com.apiguard.server.service.SpecArchiveService;
import com.apiguard.server.service.SpecStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.function.Function;

@Service
public class AnypointSyncService {

    private static final Logger log = LoggerFactory.getLogger(AnypointSyncService.class);

    private final AnypointClient client;
    private final ManifestService manifestService;
    private final ApiRepository apis;
    private final AnypointCredentials creds;
    private final SpecStore specStore;
    private final SpecArchiveService specArchive;
    private final int maxDependencyLookups;
    private final int maxSpecDownloads;

    public AnypointSyncService(AnypointClient client, ManifestService manifestService,
                               ApiRepository apis, AnypointCredentials creds,
                               SpecStore specStore, SpecArchiveService specArchive,
                               @org.springframework.beans.factory.annotation.Value(
                                       "${apiguard.anypoint.max-dependency-lookups:0}") int maxDependencyLookups,
                               @org.springframework.beans.factory.annotation.Value(
                                       "${apiguard.anypoint.max-spec-downloads:100}") int maxSpecDownloads) {
        this.client = client;
        this.manifestService = manifestService;
        this.apis = apis;
        this.creds = creds;
        this.specStore = specStore;
        this.specArchive = specArchive;
        this.maxDependencyLookups = maxDependencyLookups;
        this.maxSpecDownloads = maxSpecDownloads;
    }

    public record SyncResult(String orgId, String environmentId, String environmentName,
                             int apis, int contracts, int exchangeAssets, int dependencyEdges,
                             int consumersIngested, boolean rateLimited, String note,
                             List<String> consumers) {
    }

    private static final class Consumer {
        final LinkedHashSet<String> apis = new LinkedHashSet<>();
        String ownerTeam;
    }

    public SyncResult sync() {
        if (!client.isEnabled()) {
            throw new AnypointClient.AnypointException(
                    "Anypoint is not configured. Connect your Connected App (client id + secret) first.");
        }
        client.resetRateLimitFlag();
        String orgId = notBlank(creds.orgId()) ? creds.orgId() : client.defaultOrgId();

        List<Map<String, Object>> envs = client.environments(orgId);
        Map<String, Object> env = resolveEnv(envs);
        if (env == null) {
            throw new AnypointClient.AnypointException("No environments found for org " + orgId);
        }
        String envId = AnypointClient.str(env.get("id"));
        String envName = AnypointClient.str(env.get("name"));

        Map<String, Consumer> consumers = new LinkedHashMap<>();

        int exchangeAssetCount = exchangeGraph(orgId, consumers);
        int[] apiManagerCounts = apiManagerGraph(orgId, envId, envName, consumers);

        int dependencyEdges = consumers.values().stream().mapToInt(c -> c.apis.size()).sum();

        for (Map.Entry<String, Consumer> e : consumers.entrySet()) {
            manifestService.ingestDependency(
                    wholeApiManifest(e.getKey(), e.getValue().ownerTeam, new ArrayList<>(e.getValue().apis)));
        }

        boolean rateLimited = client.wasRateLimited();
        String note = buildNote(rateLimited, apiManagerCounts[0], exchangeAssetCount);
        log.info("Anypoint sync: org={} env={} exchangeAssets={} apis={} contracts={} edges={} consumers={} rateLimited={}",
                orgId, envName, exchangeAssetCount, apiManagerCounts[0], apiManagerCounts[1],
                dependencyEdges, consumers.size(), rateLimited);
        return new SyncResult(orgId, envId, envName, apiManagerCounts[0], apiManagerCounts[1],
                exchangeAssetCount, dependencyEdges, consumers.size(), rateLimited, note,
                new ArrayList<>(consumers.keySet()));
    }

    private static String buildNote(boolean rateLimited, int apiCount, int exchangeAssets) {
        if (rateLimited && apiCount == 0) {
            return "Anypoint rate-limited this sync — some sources were incomplete. "
                    + "The estate map shows what came through; run Sync again in a minute to fill the rest.";
        }
        if (rateLimited) {
            return "Anypoint briefly rate-limited this sync (auto-retried). Re-run Sync if anything looks missing.";
        }
        if (apiCount == 0 && exchangeAssets == 0) {
            return "No APIs found — check the Connected App has Exchange Viewer + API Manager read scopes.";
        }
        return null;
    }

    private int exchangeGraph(String orgId, Map<String, Consumer> consumers) {
        List<Map<String, Object>> assets;
        try {
            assets = client.exchangeAssets(orgId);
        } catch (RuntimeException ex) {
            log.warn("Exchange assets unavailable ({}); continuing with API Manager only.", ex.getMessage());
            return 0;
        }

        Set<String> apiAssetIds = new java.util.HashSet<>();
        for (Map<String, Object> a : assets) {
            String assetId = AnypointClient.str(a.get("assetId"));
            if (assetId != null) {
                registerApi(assetId, "exchange", displayName(a));
                apiAssetIds.add(assetId.toLowerCase());
            }
        }

        captureSpecs(assets);

        if (maxDependencyLookups <= 0) {
            return assets.size();
        }

        List<AssetCoord> coords = new ArrayList<>();
        for (Map<String, Object> a : assets) {
            String groupId = AnypointClient.str(a.get("groupId"));
            String assetId = AnypointClient.str(a.get("assetId"));
            String version = AnypointClient.str(a.get("version"));
            if (assetId != null && groupId != null && version != null) {
                coords.add(new AssetCoord(assetId, groupId, version));
            }
        }

        if (coords.size() > maxDependencyLookups) {
            log.warn("Exchange catalog has {} assets; capping dependency lookups at {} "
                    + "(raise apiguard.anypoint.max-dependency-lookups to fetch all).",
                    coords.size(), maxDependencyLookups);
            coords = coords.subList(0, maxDependencyLookups);
        }
        List<List<AnypointClient.ExchangeDep>> depLists = inParallel(coords, c -> {
            try {
                return client.exchangeAssetDependencies(c.groupId(), c.assetId(), c.version());
            } catch (RuntimeException ex) {
                return List.<AnypointClient.ExchangeDep>of();
            }
        });
        for (int i = 0; i < coords.size(); i++) {
            String assetId = coords.get(i).assetId();
            List<AnypointClient.ExchangeDep> deps = depLists.get(i);
            if (deps == null) {
                continue;
            }
            for (AnypointClient.ExchangeDep dep : deps) {
                String depId = dep.assetId();
                if (depId == null || depId.equalsIgnoreCase(assetId) || !apiAssetIds.contains(depId.toLowerCase())) {
                    continue;
                }
                consumers.computeIfAbsent(assetId, k -> new Consumer()).apis.add(depId);
            }
        }
        return assets.size();
    }

    private record AssetCoord(String assetId, String groupId, String version) {
    }

    private record CapturedSpec(String api, String version, String yaml) {
    }

    private void captureSpecs(List<Map<String, Object>> assets) {
        if (maxSpecDownloads <= 0) {
            return;
        }
        List<AssetCoord> todo = new ArrayList<>();
        for (Map<String, Object> a : assets) {
            String assetId = AnypointClient.str(a.get("assetId"));
            String groupId = AnypointClient.str(a.get("groupId"));
            String version = AnypointClient.str(a.get("version"));
            if (assetId == null || groupId == null || version == null) {
                continue;
            }
            if (specStore.hasVersionLabel(assetId, version)) {
                continue;
            }
            todo.add(new AssetCoord(assetId, groupId, version));
            if (todo.size() >= maxSpecDownloads) {
                break;
            }
        }
        if (todo.isEmpty()) {
            return;
        }
        List<CapturedSpec> captured = inParallel(todo, c -> {
            try {
                AnypointClient.AssetFile pick = pickSpecFile(client.assetFiles(c.groupId(), c.assetId(), c.version()));
                if (pick == null) {
                    return null;
                }
                byte[] bytes = client.downloadSpec(pick.externalLink());
                if (bytes == null) {
                    return null;
                }
                return new CapturedSpec(c.assetId(), c.version(), specArchive.fromBytes(bytes).spec());
            } catch (RuntimeException ex) {
                return null;
            }
        });
        int stored = 0;
        for (CapturedSpec cs : captured) {
            if (cs != null) {
                try {
                    specStore.store(cs.api(), "exchange", cs.version(), cs.yaml());
                    stored++;
                } catch (RuntimeException ignored) {
                }
            }
        }
        if (stored > 0) {
            log.info("Anypoint sync captured {} API spec(s) from Exchange", stored);
        }
    }

    public static AnypointClient.AssetFile pickSpecFile(List<AnypointClient.AssetFile> files) {
        if (files == null) {
            return null;
        }
        for (String classifier : List.of("fat-raml", "oas", "raml")) {
            for (AnypointClient.AssetFile f : files) {
                if (classifier.equalsIgnoreCase(f.classifier()) && notBlank(f.externalLink())) {
                    return f;
                }
            }
        }
        return null;
    }

    private int[] apiManagerGraph(String orgId, String envId, String envName, Map<String, Consumer> consumers) {
        List<Map<String, Object>> managed;
        try {
            managed = client.apis(orgId, envId);
        } catch (RuntimeException ex) {
            log.warn("API Manager unavailable ({}); continuing with Exchange only.", ex.getMessage());
            return new int[]{0, 0};
        }

        List<ManagedInstance> instances = new ArrayList<>();
        for (Map<String, Object> api : managed) {

            String assetId = AnypointClient.str(api.get("assetId"));
            String producer = firstNonBlank(assetId,
                    AnypointClient.str(api.get("instanceLabel")),
                    AnypointClient.str(api.get("exchangeAssetName")));
            String instanceId = AnypointClient.str(api.get("id"));
            if (producer == null || instanceId == null) {
                continue;
            }
            registerApi(producer, "anypoint", AnypointClient.str(api.get("exchangeAssetName")));
            instances.add(new ManagedInstance(producer, instanceId));
        }
        List<List<Map<String, Object>>> contractLists = inParallel(instances, in -> {
            try {
                return client.contracts(orgId, envId, in.instanceId());
            } catch (RuntimeException ex) {
                return List.<Map<String, Object>>of();
            }
        });
        int contractCount = 0;
        for (int i = 0; i < instances.size(); i++) {
            String producer = instances.get(i).producer();
            List<Map<String, Object>> contracts = contractLists.get(i);
            if (contracts == null) {
                continue;
            }
            for (Map<String, Object> contract : contracts) {
                contractCount++;
                String consumer = consumerName(contract);
                if (consumer != null && !consumer.equalsIgnoreCase(producer)) {
                    Consumer acc = consumers.computeIfAbsent(consumer, k -> new Consumer());
                    acc.apis.add(producer);
                    if (acc.ownerTeam == null) {
                        acc.ownerTeam = envName;
                    }
                }
            }
        }
        return new int[]{managed.size(), contractCount};
    }

    private record ManagedInstance(String producer, String instanceId) {
    }

    private static <T, R> List<R> inParallel(List<T> items, Function<T, R> fn) {
        if (items.isEmpty()) {
            return List.of();
        }
        ExecutorService pool = Executors.newFixedThreadPool(Math.min(8, items.size()));
        try {
            List<Future<R>> futures = new ArrayList<>(items.size());
            for (T item : items) {
                futures.add(pool.submit(() -> fn.apply(item)));
            }
            List<R> out = new ArrayList<>(items.size());
            for (Future<R> f : futures) {
                try {
                    out.add(f.get());
                } catch (Exception e) {
                    out.add(null);
                }
            }
            return out;
        } finally {
            pool.shutdownNow();
        }
    }

    private void registerApi(String id, String source, String displayName) {
        if (id != null && !id.isBlank() && apis.findByName(id).isEmpty()) {
            apis.save(new ApiEntity(id, source, null, notBlank(displayName) ? displayName : null));
        }
    }

    private static String displayName(Map<String, Object> asset) {
        return AnypointClient.str(asset.get("name"));
    }

    private Map<String, Object> resolveEnv(List<Map<String, Object>> envs) {
        if (envs.isEmpty()) {
            return null;
        }
        String configuredEnv = creds.environment();
        if (notBlank(configuredEnv)) {
            for (Map<String, Object> e : envs) {
                if (configuredEnv.equalsIgnoreCase(AnypointClient.str(e.get("name")))
                        || configuredEnv.equals(AnypointClient.str(e.get("id")))) {
                    return e;
                }
            }
        }
        return envs.get(0);
    }

    @SuppressWarnings("unchecked")
    private static String consumerName(Map<String, Object> contract) {
        Object app = contract.get("application");
        if (app instanceof Map<?, ?> m && m.get("name") != null) {
            return m.get("name").toString();
        }
        return firstNonBlank(AnypointClient.str(contract.get("applicationName")),
                AnypointClient.str(contract.get("applicationId")));
    }

    private static DependencyManifest wholeApiManifest(String consumer, String team, List<String> apis) {
        DependencyManifest m = new DependencyManifest();
        m.consumer = consumer;
        m.ownerTeam = team;
        m.reviewers = List.of();
        List<DependencyManifest.ApiDependency> deps = new ArrayList<>();
        apis.stream().distinct().forEach(api -> {
            DependencyManifest.ApiDependency dep = new DependencyManifest.ApiDependency();
            dep.api = api;
            DependencyManifest.EndpointDependency ep = new DependencyManifest.EndpointDependency();
            ep.path = "*";
            ep.fields = List.of();
            dep.endpoints = List.of(ep);
            deps.add(dep);
        });
        m.dependsOn = deps;
        return m;
    }

    private static String firstNonBlank(String... values) {
        for (String v : values) {
            if (notBlank(v)) {
                return v;
            }
        }
        return null;
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }
}
