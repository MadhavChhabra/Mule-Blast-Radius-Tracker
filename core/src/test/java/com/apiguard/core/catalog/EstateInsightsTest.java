package com.apiguard.core.catalog;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class EstateInsightsTest {

    private static EstateInsights.Node node(String name, ApiLayer layer) {
        return new EstateInsights.Node(name, layer);
    }

    private static EstateInsights.Edge edge(String from, String to) {
        return new EstateInsights.Edge(from, to);
    }

    @Test
    void cleanApiLedEstateHasNoFindings() {
        List<EstateInsights.Finding> findings = EstateInsights.analyze(
                List.of(node("shop-app", ApiLayer.APP), node("orders-exp-api", ApiLayer.EXPERIENCE),
                        node("orders-papi", ApiLayer.PROCESS), node("orders-sapi", ApiLayer.SYSTEM),
                        node("orders-db", ApiLayer.BACKEND)),
                List.of(edge("shop-app", "orders-exp-api"), edge("orders-exp-api", "orders-papi"),
                        edge("orders-papi", "orders-sapi"), edge("orders-sapi", "orders-db")));
        assertTrue(findings.isEmpty(), () -> "unexpected: " + findings);
    }

    @Test
    void upwardCallIsHighSeverity() {
        List<EstateInsights.Finding> findings = EstateInsights.analyze(
                List.of(node("orders-sapi", ApiLayer.SYSTEM), node("orders-exp-api", ApiLayer.EXPERIENCE)),
                List.of(edge("orders-sapi", "orders-exp-api")));
        assertEquals(1, findings.size());
        assertEquals("upward-call", findings.get(0).rule());
        assertEquals("high", findings.get(0).severity());
        assertEquals(List.of("orders-sapi", "orders-exp-api"), findings.get(0).apis());
    }

    @Test
    void appReachingSystemApiIsALayerSkip() {
        List<EstateInsights.Finding> findings = EstateInsights.analyze(
                List.of(node("shop-app", ApiLayer.APP), node("orders-sapi", ApiLayer.SYSTEM)),
                List.of(edge("shop-app", "orders-sapi")));
        assertEquals(1, findings.size());
        assertEquals("layer-skip", findings.get(0).rule());
        assertEquals("medium", findings.get(0).severity());
    }

    @Test
    void processToBackendIsInfoNotViolation() {
        List<EstateInsights.Finding> findings = EstateInsights.analyze(
                List.of(node("orders-papi", ApiLayer.PROCESS), node("salesforce", ApiLayer.BACKEND)),
                List.of(edge("orders-papi", "salesforce")));
        assertEquals(1, findings.size());
        assertEquals("layer-skip", findings.get(0).rule());
        assertEquals("info", findings.get(0).severity());
    }

    @Test
    void unknownLayersNeverTriggerLayerRules() {
        List<EstateInsights.Finding> findings = EstateInsights.analyze(
                List.of(node("mystery-one", ApiLayer.UNKNOWN), node("orders-exp-api", ApiLayer.EXPERIENCE)),
                List.of(edge("mystery-one", "orders-exp-api"), edge("orders-exp-api", "mystery-one")));

        assertEquals(1, findings.size());
        assertEquals("dependency-cycle", findings.get(0).rule());
    }

    @Test
    void cyclesAreDetectedIncludingSelfLoops() {
        List<EstateInsights.Finding> findings = EstateInsights.analyze(
                List.of(node("a-papi", ApiLayer.PROCESS), node("b-papi", ApiLayer.PROCESS),
                        node("c-papi", ApiLayer.PROCESS), node("loner-sapi", ApiLayer.SYSTEM)),
                List.of(edge("a-papi", "b-papi"), edge("b-papi", "c-papi"), edge("c-papi", "a-papi"),
                        edge("loner-sapi", "loner-sapi")));
        List<EstateInsights.Finding> cycles =
                findings.stream().filter(f -> f.rule().equals("dependency-cycle")).toList();
        assertEquals(2, cycles.size(), () -> "findings: " + findings);
        assertTrue(cycles.stream().anyMatch(f -> f.apis().size() == 3), "3-cycle found");
        assertTrue(cycles.stream().anyMatch(f -> f.apis().equals(List.of("loner-sapi"))), "self-loop found");
    }

    @Test
    void fanInHotspotAtThreshold() {
        List<EstateInsights.Node> nodes = new java.util.ArrayList<>();
        List<EstateInsights.Edge> edges = new java.util.ArrayList<>();
        nodes.add(node("shared-sapi", ApiLayer.SYSTEM));
        for (int i = 1; i <= EstateInsights.FAN_IN_THRESHOLD; i++) {
            nodes.add(node("consumer-" + i + "-papi", ApiLayer.PROCESS));
            edges.add(edge("consumer-" + i + "-papi", "shared-sapi"));
        }
        List<EstateInsights.Finding> findings = EstateInsights.analyze(nodes, edges);
        assertEquals(1, findings.size());
        assertEquals("change-hotspot", findings.get(0).rule());
        assertEquals("shared-sapi", findings.get(0).apis().get(0));
        assertEquals(1 + EstateInsights.FAN_IN_THRESHOLD, findings.get(0).apis().size());
    }

    @Test
    void findingsAreOrderedBySeverity() {

        List<EstateInsights.Node> nodes = new java.util.ArrayList<>(List.of(
                node("orders-sapi", ApiLayer.SYSTEM), node("orders-exp-api", ApiLayer.EXPERIENCE),
                node("shop-app", ApiLayer.APP), node("inv-sapi", ApiLayer.SYSTEM)));
        List<EstateInsights.Edge> edges = new java.util.ArrayList<>(List.of(
                edge("orders-sapi", "orders-exp-api"), edge("shop-app", "inv-sapi")));
        for (int i = 1; i <= EstateInsights.FAN_IN_THRESHOLD; i++) {
            nodes.add(node("c" + i + "-papi", ApiLayer.PROCESS));
            edges.add(edge("c" + i + "-papi", "inv-sapi"));
        }
        List<String> severities = EstateInsights.analyze(nodes, edges)
                .stream().map(EstateInsights.Finding::severity).toList();
        assertEquals(List.of("high", "medium", "info"), severities);
    }
}
