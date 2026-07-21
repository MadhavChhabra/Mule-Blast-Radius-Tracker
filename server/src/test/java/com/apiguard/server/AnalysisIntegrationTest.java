package com.apiguard.server;

import com.apiguard.core.blast.ManifestLoader;
import com.apiguard.server.service.AnalysisService;
import com.apiguard.server.service.ManifestService;
import com.apiguard.server.web.Dtos;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class AnalysisIntegrationTest {

    @Autowired
    ManifestService manifestService;
    @Autowired
    AnalysisService analysisService;

    private static final String V1 = """
            openapi: 3.0.3
            info: { title: Orders, version: 1.0.0 }
            paths:
              /orders/{id}:
                get:
                  parameters: [ { name: id, in: path, required: true, schema: { type: string } } ]
                  responses:
                    '200':
                      description: ok
                      content:
                        application/json:
                          schema:
                            type: object
                            properties:
                              id: { type: string }
                              customerId: { type: string }
            """;

    private static final String V2 = """
            openapi: 3.0.3
            info: { title: Orders, version: 2.0.0 }
            paths:
              /orders/{id}:
                get:
                  parameters: [ { name: id, in: path, required: true, schema: { type: string } } ]
                  responses:
                    '200':
                      description: ok
                      content:
                        application/json:
                          schema:
                            type: object
                            properties:
                              id: { type: string }
            """;

    @Test
    void analyzeComputesBlastRadiusAndPersists() {
        manifestService.ingestDependency(ManifestLoader.loadDependency("""
                consumer: orders-web
                owner_team: web-checkout
                reviewers: [ "gh:alice" ]
                slack_channel: "#checkout"
                depends_on:
                  - api: orders-api
                    endpoints:
                      - path: "GET /orders/{id}"
                        fields: [ "customerId" ]
                """));

        Dtos.AnalyzeResponse res = analysisService.analyze(new AnalysisService.AnalyzeCommand(
                "orders-api", "acme/orders-api", V1, V2, "v1", "v2", null, false));

        assertEquals(1, res.summary().breaking(), "customerId removal is one breaking change");
        assertEquals(1, res.summary().impactedConsumers());
        assertTrue(res.changelog().contains("Breaking"), res.changelog());

        var impact = res.impacts().stream()
                .filter(i -> i.change().classification().equals("BREAKING"))
                .findFirst().orElseThrow();
        assertTrue(impact.downstream().stream().anyMatch(c -> c.consumer().equals("orders-web")));
    }
}
