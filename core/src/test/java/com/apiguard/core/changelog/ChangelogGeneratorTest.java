package com.apiguard.core.changelog;

import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.ChangeKind;
import com.apiguard.core.diff.Classification;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertTrue;

class ChangelogGeneratorTest {

    @Test
    void groupsChangesIntoCategories() {
        List<Change> changes = List.of(
                Change.of(Classification.BREAKING, ChangeKind.RESPONSE_FIELD_REMOVED,
                        "GET /orders/{id}", "response.200.customerId", "customerId", "Response field 'customerId' removed"),
                Change.of(Classification.ADDITIVE, ChangeKind.REQUEST_FIELD_ADDED_OPTIONAL,
                        "POST /orders", "request.couponCode", "couponCode", "New optional request field 'couponCode'"),
                Change.of(Classification.ADDITIVE, ChangeKind.ENDPOINT_ADDED,
                        "GET /refunds", "/refunds", null, "Path '/refunds' was added"));

        String md = new ChangelogGenerator().generate(changes, "v2.0.0 (2026-07-11)");

        assertTrue(md.contains("## v2.0.0 (2026-07-11)"), md);
        assertTrue(md.contains("⚠️ Breaking Changes"), md);
        assertTrue(md.contains("### Added"), md);
        assertTrue(md.contains("customerId"), md);
        assertTrue(md.contains("Ship it safely:"), "should include remediation guidance\n" + md);
        assertTrue(md.contains("new major version"), "remediation should name the safe path\n" + md);
        assertTrue(md.contains("3 changes, 1 breaking"), md);
    }

    @Test
    void emptyDiffProducesFriendlyMessage() {
        String md = new ChangelogGenerator().generate(List.of());
        assertTrue(md.contains("No API changes detected"), md);
    }
}
