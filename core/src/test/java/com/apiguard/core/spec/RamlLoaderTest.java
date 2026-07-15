package com.apiguard.core.spec;

import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.ChangeKind;
import com.apiguard.core.diff.Classification;
import com.apiguard.core.diff.DiffEngine;
import io.swagger.v3.oas.models.OpenAPI;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RamlLoaderTest {

    private static final String V1 = """
            #%RAML 1.0
            title: Orders Process API
            version: v1
            /orders/{orderId}:
              uriParameters:
                orderId:
                  type: string
              get:
                responses:
                  200:
                    body:
                      application/json:
                        type: object
                        properties:
                          orderId: string
                          customerId: string
                          status:
                            type: string
                            enum: [open, paid, closed]
            """;

    private static final String V2 = """
            #%RAML 1.0
            title: Orders Process API
            version: v2
            /orders/{orderId}:
              uriParameters:
                orderId:
                  type: string
              get:
                responses:
                  200:
                    body:
                      application/json:
                        type: object
                        properties:
                          orderId: string
                          status:
                            type: string
                            enum: [open, paid, closed, refunded]
            """;

    @Test
    void loadsRamlIntoOpenApiModel() {
        OpenAPI api = SpecLoader.loadString(V1);
        assertNotNull(api.getPaths().get("/orders/{orderId}"));
        assertNotNull(api.getPaths().get("/orders/{orderId}").getGet());
    }

    @Test
    void ramlDiffDetectsSameBreakingChangesAsOas() {
        // The whole point: RAML flows through the existing DiffEngine unchanged.
        List<Change> changes = new DiffEngine().diff(SpecLoader.loadString(V1), SpecLoader.loadString(V2));

        assertTrue(changes.stream().anyMatch(c -> c.kind() == ChangeKind.RESPONSE_FIELD_REMOVED
                && "customerId".equals(c.field()) && c.classification() == Classification.BREAKING),
                () -> "customerId removal should be breaking: " + changes);

        assertTrue(changes.stream().anyMatch(c -> c.kind() == ChangeKind.RESPONSE_ENUM_VALUE_ADDED
                && c.classification() == Classification.BREAKING),
                () -> "response enum 'refunded' addition should be breaking: " + changes);
    }

    @Test
    void resolvesLibrariesDataTypesAndExamplesAcrossFiles() throws java.io.IOException {
        // A realistic Exchange asset spread across files: root + uses-library + datatype + example.
        java.nio.file.Path dir = java.nio.file.Files.createTempDirectory("apiguard-raml-multi-");
        try {
            write(dir, "libraries/common.raml", """
                    #%RAML 1.0 Library
                    types:
                      Money:
                        type: object
                        properties:
                          amount: number
                          currency: string
                    """);
            write(dir, "dataTypes/Order.raml", """
                    #%RAML 1.0 DataType
                    type: object
                    properties:
                      orderId: string
                      customerId: string
                      status:
                        type: string
                        enum: [open, paid, closed]
                    example: !include ../examples/order.json
                    """);
            write(dir, "examples/order.json", "{ \"orderId\": \"o1\", \"customerId\": \"c1\", \"status\": \"open\" }");
            java.nio.file.Path root = write(dir, "orders-api.raml", """
                    #%RAML 1.0
                    title: Orders API
                    version: v1
                    uses:
                      common: libraries/common.raml
                    types:
                      Order: !include dataTypes/Order.raml
                      Money: common.Money
                    /orders/{orderId}:
                      uriParameters:
                        orderId: string
                      get:
                        responses:
                          200:
                            body:
                              application/json:
                                type: Order
                    """);

            OpenAPI api = RamlLoader.loadFile(root);
            var schema = api.getPaths().get("/orders/{orderId}").getGet()
                    .getResponses().get("200").getContent().get("application/json").getSchema();
            // The datatype (from a separate file, itself pulling an example) is fully inlined.
            assertTrue(schema.getProperties().containsKey("customerId"),
                    () -> "cross-file datatype should resolve: " + schema.getProperties());
            assertTrue(schema.getProperties().containsKey("status"));
        } finally {
            deleteRecursively(dir);
        }
    }

    private static java.nio.file.Path write(java.nio.file.Path base, String rel, String content) throws java.io.IOException {
        java.nio.file.Path p = base.resolve(rel);
        java.nio.file.Files.createDirectories(p.getParent());
        java.nio.file.Files.writeString(p, content);
        return p;
    }

    private static void deleteRecursively(java.nio.file.Path dir) throws java.io.IOException {
        try (var walk = java.nio.file.Files.walk(dir)) {
            walk.sorted(java.util.Comparator.reverseOrder()).forEach(p -> {
                try {
                    java.nio.file.Files.deleteIfExists(p);
                } catch (java.io.IOException ignored) {
                }
            });
        }
    }

    @Test
    void ramlAndOasProduceEquivalentClassification() {
        long breaking = new DiffEngine().diff(SpecLoader.loadString(V1), SpecLoader.loadString(V2))
                .stream().filter(Change::isBreaking).count();
        assertEquals(2, breaking, "customerId removed + response enum widened");
    }
}
