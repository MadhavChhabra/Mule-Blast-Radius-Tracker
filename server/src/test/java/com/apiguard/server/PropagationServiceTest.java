package com.apiguard.server;

import com.apiguard.core.blast.ManifestLoader;
import com.apiguard.server.service.ManifestService;
import com.apiguard.server.service.PropagationService;
import com.apiguard.server.web.Dtos;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class PropagationServiceTest {

    @Autowired
    ManifestService manifestService;
    @Autowired
    PropagationService propagation;

    private static final String SPEC = """
            openapi: 3.0.3
            info: { title: Orders API, version: 1.2.0 }
            paths:
              /orders/{id}:
                get:
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
                              status: { type: string }
            """;

    @Test
    void flagsOnlyFieldsAConsumerReads() {
        manifestService.ingestDependency(ManifestLoader.loadDependency("""
                consumer: orders-web
                owner_team: web-checkout
                reviewers: [ "gh:alice" ]
                depends_on:
                  - api: orders-prop-api
                    endpoints:
                      - path: "GET /orders/{id}"
                        fields: [ "customerId" ]
                """));

        Dtos.PropagationResponse res = propagation.propagate("orders-prop-api", SPEC);

        assertEquals("Orders API", res.title());
        assertEquals(3, res.fields(), "three response fields on the endpoint");

        var customerId = res.items().stream()
                .filter(f -> f.field().equals("customerId")).findFirst().orElseThrow();
        assertEquals(1, customerId.consumerCount(), "customerId is read by one consumer");
        assertTrue(customerId.downstream().stream().anyMatch(c -> c.consumer().equals("orders-web")));

        var status = res.items().stream()
                .filter(f -> f.field().equals("status")).findFirst().orElseThrow();
        assertEquals(0, status.consumerCount(), "status is read by no one → safe to change");

        assertEquals("customerId", res.items().get(0).field());
    }
}
