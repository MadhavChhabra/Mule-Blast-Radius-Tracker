package com.apiguard.core.blast;

public final class RiskScorer {

    public enum Level {NONE, LOW, MEDIUM, HIGH, CRITICAL}

    public record Risk(int score, Level level) {
    }

    private RiskScorer() {
    }

    public static Risk score(int breakingChanges, int additiveChanges, int impactedConsumers) {
        int score = 0;
        if (breakingChanges > 0) {
            score += 10;
        }
        score += Math.min(30, breakingChanges * 10);
        score += Math.min(50, impactedConsumers * 20);
        score += Math.min(5, additiveChanges);
        score = Math.max(0, Math.min(100, score));
        return new Risk(score, level(score, breakingChanges));
    }

    private static Level level(int score, int breakingChanges) {

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
