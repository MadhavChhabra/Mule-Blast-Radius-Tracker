package com.apiguard.server;

import com.apiguard.core.blast.ManifestLoader;
import com.apiguard.server.service.EndpointInspectorService;
import com.apiguard.server.service.ManifestService;
import com.apiguard.server.web.Dtos;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class EndpointInspectorServiceTest {

    @Autowired
    ManifestService manifestService;
    @Autowired
    EndpointInspectorService inspector;

    @Test
    void showsCallsAndCallersForOneEndpoint() {

        manifestService.ingestDependency(ManifestLoader.loadDependency("""
                consumer: insp-exp-api
                owner_team: orders-experience
                depends_on:
                  - api: insp-process-api
                    endpoints:
                      - path: "GET /orders/{id}"
                        consumer_endpoint: "GET /orders/{id}"
                        fields: [ "customerId" ]
                  - api: Database
                    endpoints:
                      - path: "SELECT accounts"
                        consumer_endpoint: "GET /orders/{id}"
                """));

        manifestService.ingestDependency(ManifestLoader.loadDependency("""
                consumer: insp-web-app
                owner_team: web
                depends_on:
                  - api: insp-exp-api
                    endpoints:
                      - path: "GET /orders/{id}"
                        consumer_endpoint: "GET /orders"
                        fields: [ "status" ]
                """));

        Dtos.EndpointInspectDto dto = inspector.inspect("insp-exp-api", "GET /orders/{id}");

        assertTrue(dto.endpoints().contains("GET /orders/{id}"), "endpoint surface");

        assertEquals(2, dto.calls().size(), () -> "calls: " + dto.calls());
        assertTrue(dto.calls().stream().anyMatch(p -> p.api().equals("insp-process-api")));
        var db = dto.calls().stream().filter(p -> p.api().equals("Database")).findFirst().orElseThrow();
        assertEquals("BACKEND", db.layer(), "the database is classified as a system of record");

        assertEquals(1, dto.calledBy().size(), () -> "calledBy: " + dto.calledBy());
        var caller = dto.calledBy().get(0);
        assertEquals("insp-web-app", caller.consumer());
        assertEquals("GET /orders", caller.viaEndpoint());
        assertTrue(caller.fields().contains("status"));
    }
}
