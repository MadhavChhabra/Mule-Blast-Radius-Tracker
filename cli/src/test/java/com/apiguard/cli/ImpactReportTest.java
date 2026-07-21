package com.apiguard.cli;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ImpactReportTest {

    private static final String RESPONSE = """
            {
              "api": "orders-api",
              "summary": {"total": 3, "breaking": 1, "safe": 1, "additive": 1, "impactedConsumers": 2},
              "advisory": {"recommendedBump": "MAJOR", "currentVersion": "1.2.0", "nextVersion": "2.0.0",
                           "riskScore": 72, "riskLevel": "HIGH"},
              "impacts": [
                {"change": {"classification": "BREAKING", "kind": "FIELD_REMOVED",
                            "endpoint": "GET /orders/{id}", "field": "total",
                            "description": "Response field 'total' removed"},
                 "downstream": [
                    {"consumer": "billing-service", "ownerTeam": "billing",
                     "reviewers": ["gh:carol"], "matchedField": "total"},
                    {"consumer": "orders-web", "ownerTeam": "web", "reviewers": [], "matchedField": "total"}],
                 "upstream": []},
                {"change": {"classification": "ADDITIVE", "kind": "FIELD_ADDED",
                            "endpoint": "GET /orders/{id}", "field": "note",
                            "description": "Response field 'note' added"},
                 "downstream": [], "upstream": []}
              ],
              "changelog": "## orders-api before -> after\\n- removed total"
            }""";

    private static JsonNode parse(String json) throws Exception {
        return new ObjectMapper().readTree(json);
    }

    @Test
    void markdownCarriesRiskBreakingAndConsumers() throws Exception {
        String md = ImpactReport.renderMarkdown(parse(RESPONSE));
        assertTrue(md.contains("Wakegraph impact — `orders-api`"), md);
        assertTrue(md.contains("Deployment risk: HIGH (72/100)"), md);
        assertTrue(md.contains("**MAJOR** (1.2.0 → 2.0.0)"), md);
        assertTrue(md.contains("`GET /orders/{id}` — Response field 'total' removed"), md);
        assertTrue(md.contains("breaks **billing-service** (team billing, review: @carol) — uses `total`"), md);
        assertTrue(md.contains("<details><summary>Changelog</summary>"), md);
        assertFalse(md.contains("No breaking changes"), "breaking section replaces the all-clear line");
    }

    @Test
    void cleanResponseSaysAllClear() throws Exception {
        JsonNode clean = parse("""
                {"api": "orders-api",
                 "summary": {"total": 1, "breaking": 0, "safe": 0, "additive": 1, "impactedConsumers": 0},
                 "advisory": {"recommendedBump": "MINOR", "riskScore": 5, "riskLevel": "LOW"},
                 "impacts": [], "changelog": ""}""");
        String md = ImpactReport.renderMarkdown(clean);
        assertTrue(md.contains("✅ No breaking changes."), md);
        assertFalse(md.contains("<details>"), "no changelog block when changelog is empty");
    }

    @Test
    void markdownShowsConsumerReadinessWhenPresent() throws Exception {
        JsonNode withReadiness = parse("""
                {"api": "orders-api",
                 "summary": {"total": 1, "breaking": 1, "safe": 0, "additive": 0, "impactedConsumers": 1},
                 "advisory": {"recommendedBump": "MAJOR", "riskScore": 60, "riskLevel": "HIGH"},
                 "impacts": [
                   {"change": {"classification": "BREAKING", "kind": "FIELD_REMOVED",
                               "endpoint": "GET /orders/{id}", "field": "total",
                               "description": "Response field 'total' removed"},
                    "downstream": [
                      {"consumer": "billing-service", "ownerTeam": "billing", "reviewers": [],
                       "matchedField": "total", "discoveredOnly": true,
                       "lastSeenAt": "2026-07-15T10:20:30Z"}],
                    "upstream": []}
                 ], "changelog": ""}""");
        String md = ImpactReport.renderMarkdown(withReadiness);
        assertTrue(md.contains("_discovered — no manifest committed_"), md);
        assertTrue(md.contains("last seen 2026-07-15"), md);
    }

    @Test
    void exitCodesFollowFailOnMode() throws Exception {
        JsonNode withImpact = parse(RESPONSE);
        assertEquals(1, ImpactReport.exitCode(withImpact, ImpactReport.FailOn.BREAKING_IMPACT));
        assertEquals(1, ImpactReport.exitCode(withImpact, ImpactReport.FailOn.BREAKING));
        assertEquals(0, ImpactReport.exitCode(withImpact, ImpactReport.FailOn.NEVER));

        JsonNode noConsumers = parse("""
                {"summary": {"total": 1, "breaking": 1, "safe": 0, "additive": 0, "impactedConsumers": 0}}""");
        assertEquals(0, ImpactReport.exitCode(noConsumers, ImpactReport.FailOn.BREAKING_IMPACT));
        assertEquals(1, ImpactReport.exitCode(noConsumers, ImpactReport.FailOn.BREAKING));
    }
}
