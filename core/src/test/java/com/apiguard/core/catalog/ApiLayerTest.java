package com.apiguard.core.catalog;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ApiLayerTest {

    @Test
    void classifiesByMuleSoftNamingConvention() {
        assertEquals(ApiLayer.SYSTEM, ApiLayer.classify("gm-micorp-sapi"));
        assertEquals(ApiLayer.SYSTEM, ApiLayer.classify("hr-portal-sys-api-dev")); // system wins over "portal"
        assertEquals(ApiLayer.PROCESS, ApiLayer.classify("gm-micorp-papi"));
        assertEquals(ApiLayer.EXPERIENCE, ApiLayer.classify("orders-exp-api"));
        assertEquals(ApiLayer.EXPERIENCE, ApiLayer.classify("mobile-eapi"));
        assertEquals(ApiLayer.APP, ApiLayer.classify("Test MiCorp Application"));
        assertEquals(ApiLayer.APP, ApiLayer.classify("health-app"));
        assertEquals(ApiLayer.UNKNOWN, ApiLayer.classify("american-flights-apis"));
    }

    @Test
    void classifiesEndSystemsAsBackend() {
        assertEquals(ApiLayer.BACKEND, ApiLayer.classify("Salesforce"));
        assertEquals(ApiLayer.BACKEND, ApiLayer.classify("Database"));
        assertEquals(ApiLayer.BACKEND, ApiLayer.classify("orders-db"));
        assertEquals(ApiLayer.BACKEND, ApiLayer.classify("JMS Queue"));
        assertEquals(ApiLayer.BACKEND, ApiLayer.classify("SAP"));
        // "sap" as a token must not swallow the "sapi" system-API suffix.
        assertEquals(ApiLayer.SYSTEM, ApiLayer.classify("gm-micorp-sapi"));
    }
}
