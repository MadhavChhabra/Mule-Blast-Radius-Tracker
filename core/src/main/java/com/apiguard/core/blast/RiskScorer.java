package com.apiguard.core.blast;

/**
 * Computes a deployment risk score (0–100) and level from a change's blast radius. The score rises
 * with breaking changes and — more sharply — with the number of real consumers those breaking
 * changes reach, since consumer impact is what actually causes production incidents.
 */
public final class RiskScorer {

    public enum Level {NONE, LOW, MEDIUM, HIGH, CRITICAL}

    public record Risk(int score, Level level) {
    }

    private RiskScorer() {
    }

    /**
     * @param breakingChanges   number of breaking changes
     * @param additiveChanges   number of additive changes (mild signal)
     * @param impactedConsumers distinct consumers hit by a breaking change
     */
    public static Risk score(int breakingChanges, int additiveChanges, int impactedConsumers) {
        int score = 0;
        if (breakingChanges > 0) {
            score += 10;                                   // any breaking change carries baseline risk
        }
        score += Math.min(30, breakingChanges * 10);      // breaking changes themselves
        score += Math.min(50, impactedConsumers * 20);    // real downstream blast is the big driver
        score += Math.min(5, additiveChanges);            // additive surface area, minor
        score = Math.max(0, Math.min(100, score));
        return new Risk(score, level(score, breakingChanges));
    }

    private static Level level(int score, int breakingChanges) {
        // Safe / additive changes don't break consumers → no deployment risk.
        if (breakingChanges == 0) {
            return Level.NONE;
        }
        if (score >= 75) {
            return Level.CRITICAL;
        }
        if (score >= 50) {
            return Level.HIGH;
        }
        if (score >= 25) {
            return Level.MEDIUM;
        }
        return Level.LOW;
    }
}
