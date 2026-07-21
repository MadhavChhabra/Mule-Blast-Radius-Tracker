package com.apiguard.server;

import com.apiguard.server.anypoint.AnypointClient;
import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.anypoint.AnypointSyncService;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.service.GraphService;
import com.apiguard.server.service.ManifestService;
import com.apiguard.server.web.Dtos;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class AnypointSyncServiceTest {

    @Autowired
    ManifestService manifestService;
    @Autowired
    ApiRepository apis;
    @Autowired
    GraphService graphService;
    @Autowired
    AnypointCredentials creds;

    private AnypointClient fakeClient() {
        return new AnypointClient("http://localhost", 1000, 2, creds) {
            @Override
            public boolean isEnabled() {
                return true;
            }

            @Override
            public List<Map<String, Object>> environments(String orgId) {
                return List.of(Map.of("id", "envA", "name", "Sandbox"));
            }

            @Override
            public List<Map<String, Object>> exchangeAssets(String orgId) {
                return List.of(
                        Map.of("groupId", "g", "assetId", "orders-exp-api",
                                "name", "Orders Experience API", "version", "1.0.0"),
                        Map.of("groupId", "g", "assetId", "orders-proc-api",
                                "name", "Orders Process API", "version", "1.0.0"),
                        Map.of("groupId", "g", "assetId", "orders-sys-api",
                                "name", "Orders System API", "version", "1.0.0"));
            }

            @Override
            public List<ExchangeDep> exchangeAssetDependencies(String groupId, String assetId, String version) {
                return switch (assetId) {
                    case "orders-exp-api" -> List.of(new ExchangeDep("orders-proc-api", "Orders Process API"));
                    case "orders-proc-api" -> List.of(new ExchangeDep("orders-sys-api", "Orders System API"));

                    case "orders-sys-api" -> List.of(new ExchangeDep("common-types-fragment", "Common Types"));
                    default -> List.of();
                };
            }

            @Override
            public List<Map<String, Object>> apis(String orgId, String envId) {

                return List.of(Map.of("id", "inst1", "assetId", "orders-exp-api", "instanceLabel", "exp"));
            }

            @Override
            public List<Map<String, Object>> contracts(String orgId, String envId, String apiInstanceId) {
                return List.of(Map.of("application", Map.of("name", "orders-mobile-app")));
            }
        };
    }

    @Test
    void syncBuildsExchangeAndContractGraph() {
        creds.update("cid", "csecret", "org1", "Sandbox");
        AnypointSyncService sync = new AnypointSyncService(fakeClient(), manifestService, apis, creds, 1500);

        AnypointSyncService.SyncResult result = sync.sync();

        assertEquals(3, result.exchangeAssets(), "three Exchange assets seen");

        assertEquals(3, result.dependencyEdges());
        assertEquals(false, result.rateLimited(), "no rate limiting in the happy path");

        Dtos.GraphDto graph = graphService.build();

        assertTrue(hasNode(graph, "orders-exp-api"), "exp API node present (by assetId)");
        assertTrue(hasNode(graph, "orders-sys-api"), "system API node present (by assetId)");
        assertEquals("Orders Experience API",
                graph.nodes().stream().filter(n -> n.id().equals("orders-exp-api")).findFirst().orElseThrow().label(),
                "node carries the human display label");

        assertTrue(hasEdge(graph, "orders-exp-api", "orders-proc-api"), "exp → proc");
        assertTrue(hasEdge(graph, "orders-proc-api", "orders-sys-api"), "proc → sys");

        assertTrue(hasEdge(graph, "orders-mobile-app", "orders-exp-api"), "app → exp");

        assertTrue(graph.nodes().stream().noneMatch(n -> n.id().equals("common-types-fragment")),
                "fragment dependency must not become a node");
        assertTrue(graph.edges().stream().noneMatch(e -> e.to().equals("common-types-fragment")),
                "fragment dependency must not become an edge");
    }

    private static boolean hasNode(Dtos.GraphDto g, String id) {
        return g.nodes().stream().anyMatch(n -> n.id().equals(id));
    }

    private static boolean hasEdge(Dtos.GraphDto g, String from, String to) {
        return g.edges().stream().anyMatch(e -> e.from().equals(from) && e.to().equals(to));
    }
}
