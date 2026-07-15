package com.apiguard.core.diff;

import com.apiguard.core.blast.RiskScorer;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;

class VersionAdvisorTest {

    private static Change c(Classification cl) {
        return Change.of(cl, ChangeKind.RESPONSE_FIELD_ADDED, "GET /x", "response.x", "x", "d");
    }

    @Test
    void breakingRecommendsMajor() {
        assertEquals(VersionAdvisor.Bump.MAJOR,
                VersionAdvisor.recommend(List.of(c(Classification.BREAKING), c(Classification.ADDITIVE))));
        assertEquals("2.0.0", VersionAdvisor.nextVersion("1.4.2", VersionAdvisor.Bump.MAJOR));
    }

    @Test
    void additiveRecommendsMinor() {
        assertEquals(VersionAdvisor.Bump.MINOR, VersionAdvisor.recommend(List.of(c(Classification.ADDITIVE))));
        assertEquals("1.5.0", VersionAdvisor.nextVersion("1.4.2", VersionAdvisor.Bump.MINOR));
        assertEquals("v2.1.0", VersionAdvisor.nextVersion("v2.0.9", VersionAdvisor.Bump.MINOR));
    }

    @Test
    void nonBreakingOnlyRecommendsPatch() {
        assertEquals(VersionAdvisor.Bump.PATCH, VersionAdvisor.recommend(List.of(c(Classification.NON_BREAKING))));
        assertEquals("1.4.3", VersionAdvisor.nextVersion("1.4.2", VersionAdvisor.Bump.PATCH));
    }

    @Test
    void noChangesRecommendsNone() {
        assertEquals(VersionAdvisor.Bump.NONE, VersionAdvisor.recommend(List.of()));
    }

    @Test
    void riskRisesWithImpactedConsumers() {
        var safe = RiskScorer.score(0, 2, 0);
        assertEquals(RiskScorer.Level.NONE, safe.level());

        var oneBreakingNoConsumers = RiskScorer.score(1, 0, 0);
        assertEquals(RiskScorer.Level.LOW, oneBreakingNoConsumers.level());

        var breakingHittingManyConsumers = RiskScorer.score(3, 0, 3);
        assertEquals(RiskScorer.Level.CRITICAL, breakingHittingManyConsumers.level());
    }
}
