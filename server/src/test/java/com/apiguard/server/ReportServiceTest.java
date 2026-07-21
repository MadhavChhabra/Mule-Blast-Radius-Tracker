package com.apiguard.server;

import com.apiguard.core.blast.ManifestLoader;
import com.apiguard.server.service.ManifestService;
import com.apiguard.server.service.ReportService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class ReportServiceTest {

    @Autowired
    ReportService report;
    @Autowired
    ManifestService manifests;

    @Test
    void reportContainsEstateGovernanceAndConsumers() {

        manifests.ingestDependency(ManifestLoader.loadDependency("""
                consumer: rpt-billing-app
                owner_team: rpt-billing
                depends_on:
                  - api: rpt-orders-exp-api
                    endpoints:
                      - path: "GET /orders"
                        fields: [ "total" ]
                """));
        manifests.ingestDependency(ManifestLoader.loadDependency("""
                consumer: rpt-orders-sys-api
                depends_on:
                  - api: rpt-orders-exp-api
                    endpoints:
                      - path: "GET /orders"
                """));

        String md = report.markdown();

        assertTrue(md.startsWith("# Wakegraph estate report"), md.substring(0, Math.min(120, md.length())));
        assertTrue(md.contains("## Estate at a glance"));
        assertTrue(md.contains("## Governance findings"));
        assertTrue(md.contains("Upward call: rpt-orders-sys-api → rpt-orders-exp-api"),
                "the seeded upward call is reported");
        assertTrue(md.contains("## Who consumes what"));
        assertTrue(md.contains("`rpt-orders-exp-api` — 2 consumer(s)")
                        || md.contains("`rpt-orders-exp-api` —"),
                "consumer section lists the API");
        assertTrue(md.contains("`rpt-billing-app` via GET /orders"), "via endpoints are shown");
    }
}
