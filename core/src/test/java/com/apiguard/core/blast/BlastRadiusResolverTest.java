package com.apiguard.core.blast;

import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.ChangeKind;
import com.apiguard.core.diff.Classification;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class BlastRadiusResolverTest {

    private static BlastRadiusResolver resolver() {
        DependencyManifest ordersWeb = ManifestLoader.loadDependency("""
                consumer: orders-web
                owner_team: web-checkout
                reviewers: [ "gh:alice", "gh:bob" ]
                slack_channel: "#checkout-alerts"
                depends_on:
                  - api: orders-api
                    endpoints:
                      - path: "GET /orders/{id}"
                        fields: [ "customerId", "status" ]
                """);
        DependencyManifest billing = ManifestLoader.loadDependency("""
                consumer: billing-service
                owner_team: billing
                reviewers: [ "gh:carol" ]
                slack_channel: "#billing"
                depends_on:
                  - api: orders-api
                    endpoints:
                      - path: "GET /orders/{id}"
                        fields: [ "customerId" ]
                """);
        FieldSourceManifest sources = ManifestLoader.loadSources("""
                api: orders-api
                sources:
                  - endpoint: "GET /orders/{id}"
                    field: "customerId"
                    from: { api: customers-api, endpoint: "GET /customers/{id}", field: "id" }
                """);
        return new BlastRadiusResolver(List.of(ordersWeb, billing), List.of(sources));
    }

    @Test
    void fieldLevelDownstreamMatching() {

        Change removed = Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                "GET /orders/{id}", "response.200.customerId", "customerId", "removed");
        var impact = resolver().resolve("orders-api", List.of(removed)).get(0);
        assertEquals(2, impact.downstream().size());
        assertTrue(impact.downstream().stream().anyMatch(c -> c.consumer().equals("orders-web")));
        assertTrue(impact.downstream().stream().anyMatch(c -> c.consumer().equals("billing-service")));
    }

    @Test
    void fieldPrecisionExcludesUnrelatedConsumers() {

        Change statusChange = Change.of(Classification.BREAKING, ChangeKind.RESPONSE_ENUM_VALUE_ADDED,
                "GET /orders/{id}", "response.200.status", "status", "enum added");
        var impact = resolver().resolve("orders-api", List.of(statusChange)).get(0);
        assertEquals(1, impact.downstream().size());
        assertEquals("orders-web", impact.downstream().get(0).consumer());
    }

    @Test
    void upstreamLineageResolved() {
        Change removed = Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                "GET /orders/{id}", "response.200.customerId", "customerId", "removed");
        var impact = resolver().resolve("orders-api", List.of(removed)).get(0);
        assertEquals(1, impact.upstream().size());
        assertEquals("customers-api", impact.upstream().get(0).api());
    }

    @Test
    void endpointLevelChangeImpactsAllConsumers() {
        Change opRemoved = Change.of(Classification.BREAKING, ChangeKind.OPERATION_REMOVED,
                "GET /orders/{id}", "GET /orders/{id}", null, "operation removed");
        var impact = resolver().resolve("orders-api", List.of(opRemoved)).get(0);
        assertEquals(2, impact.downstream().size());
    }

    @Test
    void wholeApiDependencyMatchesAnyEndpoint() {

        DependencyManifest wholeApi = ManifestLoader.loadDependency("""
                consumer: mobile-app
                owner_team: mobile
                depends_on:
                  - api: orders-api
                    endpoints:
                      - path: "*"
                """);
        var resolver = new BlastRadiusResolver(List.of(wholeApi), List.of());
        Change anyChange = Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                "GET /orders/{id}", "response.200.total", "total", "removed");
        var impact = resolver.resolve("orders-api", List.of(anyChange)).get(0);
        assertTrue(impact.downstream().stream().anyMatch(c -> c.consumer().equals("mobile-app")));
    }

    @Test
    void unrelatedApiHasNoImpact() {
        Change removed = Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                "GET /orders/{id}", "response.200.customerId", "customerId", "removed");
        var impact = resolver().resolve("some-other-api", List.of(removed)).get(0);
        assertFalse(impact.hasImpact());
    }
}
