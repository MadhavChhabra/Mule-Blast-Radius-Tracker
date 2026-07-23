package com.apiguard.core.diff;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class RemediationTest {

    private static Change change(Classification classification, ChangeKind kind) {
        return Change.of(classification, kind, "GET /orders/{id}", "response.200.customerId",
                "customerId", kind.label());
    }

    @Test
    void everyBreakingKindHasGuidance() {
        for (ChangeKind kind : ChangeKind.values()) {
            if (kind.defaultClassification() != Classification.BREAKING) {
                continue;
            }
            String hint = Remediation.forChange(change(Classification.BREAKING, kind));
            assertNotNull(hint, "no remediation for breaking kind " + kind);
            assertTrue(hint.length() > 20, "remediation too short for " + kind + ": " + hint);
        }
    }

    @Test
    void safeAndAdditiveChangesGetNoNoise() {
        assertNull(Remediation.forChange(change(Classification.ADDITIVE, ChangeKind.RESPONSE_FIELD_ADDED)));
        assertNull(Remediation.forChange(change(Classification.NON_BREAKING, ChangeKind.REQUEST_FIELD_REMOVED)));
    }

    @Test
    void removedResponseFieldPointsToDeprecateThenMajor() {
        String hint = Remediation.forChange(change(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED));
        assertTrue(hint.contains("deprecated"), hint);
        assertTrue(hint.contains("new major version"), hint);
    }

    @Test
    void requiredRequestFieldPointsToOptionalDefault() {
        String hint = Remediation.forChange(change(Classification.BREAKING, ChangeKind.REQUEST_FIELD_ADDED_REQUIRED));
        assertTrue(hint.contains("optional"), hint);
    }

    @Test
    void nullChangeIsNull() {
        assertNull(Remediation.forChange(null));
    }
}
