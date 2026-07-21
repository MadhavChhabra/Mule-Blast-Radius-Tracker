package com.apiguard.core.mule;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MuleScanCoverageTest {

    @Test
    void undeclaredCallsAreCallsToApisMissingFromPom() {
        MuleScan scan = new MuleScan(
                "orders-exp-api", "com.acme", "1.0.0", MuleScan.Owner.empty(),
                List.of(new MuleScan.InboundEndpoint("GET", "/orders", List.of(
                        new MuleScan.OutboundCall("orders-process-api", "GET", "/orders", "orders-cfg"),
                        new MuleScan.OutboundCall("billing-svc", "POST", "/charges", "billing-cfg")
                ))),
                List.of("orders-process-api", "customers-sys-api"),
                List.of());

        assertEquals(List.of("billing-svc"), scan.undeclaredCalls());
    }

    @Test
    void unknownAndBlankApisAreIgnored() {
        MuleScan scan = new MuleScan(
                "orders-exp-api", "com.acme", "1.0.0", MuleScan.Owner.empty(),
                List.of(),
                List.of("orders-process-api"),
                List.of(
                        new MuleScan.OutboundCall("unknown", "GET", "/x", null),
                        new MuleScan.OutboundCall("", "GET", "/y", null),
                        new MuleScan.OutboundCall("orders-process-api", "GET", "/orders", null)));

        assertTrue(scan.undeclaredCalls().isEmpty());
    }

    @Test
    void caseInsensitiveMatchAgainstDeclared() {
        MuleScan scan = new MuleScan(
                "app", null, null, MuleScan.Owner.empty(),
                List.of(), List.of("Orders-Process-Api"),
                List.of(new MuleScan.OutboundCall("orders-process-api", "GET", "/x", null)));

        assertTrue(scan.undeclaredCalls().isEmpty());
    }
}
