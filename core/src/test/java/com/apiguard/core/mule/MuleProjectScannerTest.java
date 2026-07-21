package com.apiguard.core.mule;

import com.apiguard.core.blast.DependencyManifest;
import org.junit.jupiter.api.Test;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class MuleProjectScannerTest {

    private static Path sampleProject() {
        for (Path base : new Path[]{Path.of("samples/mule/orders-exp-api"),
                Path.of("../samples/mule/orders-exp-api")}) {
            if (Files.isDirectory(base)) {
                return base;
            }
        }
        throw new IllegalStateException("sample Mule project not found");
    }

    @Test
    void scanExtractsAppNameAndDeclaredApis() {
        MuleScan scan = MuleProjectScanner.scan(sampleProject());
        assertEquals("orders-exp-api", scan.app());

        assertTrue(scan.declaredApis().contains("orders-process-api"));
        assertTrue(scan.declaredApis().contains("customers-sys-api"));
        assertEquals(2, scan.declaredApis().size(), () -> "connectors must be filtered: " + scan.declaredApis());
    }

    @Test
    void scanMapsPerEndpointDownstreamCalls() {
        MuleScan scan = MuleProjectScanner.scan(sampleProject());
        assertEquals(3, scan.endpoints().size());

        var getOrderById = scan.endpoints().stream()
                .filter(e -> e.label().equals("GET /orders/{orderId}"))
                .findFirst().orElseThrow();

        assertEquals(2, getOrderById.calls().size());
        assertTrue(getOrderById.calls().stream()
                .anyMatch(c -> c.api().equals("orders-process-api") && c.endpoint().equals("GET /orders/{orderId}")));
        assertTrue(getOrderById.calls().stream()
                .anyMatch(c -> c.api().equals("customers-sys-api") && c.endpoint().equals("GET /customers/{id}")));
    }

    @Test
    void resolvesDownstreamApiFromPropertiesAndConfigHost() throws java.io.IOException {

        java.nio.file.Path dir = java.nio.file.Files.createTempDirectory("apiguard-props-");
        try {
            write(dir, "pom.xml", """
                    <project xmlns="http://maven.apache.org/POM/4.0.0">
                      <modelVersion>4.0.0</modelVersion>
                      <groupId>com.acme</groupId><artifactId>billing-exp-api</artifactId><version>1.0.0</version>
                    </project>
                    """);
            write(dir, "src/main/resources/config/props.yaml", """
                    billing:
                      payments:
                        host: payments-sys-api.acme.internal
                    """);
            write(dir, "src/main/mule/global.xml", """
                    <mule xmlns="http://www.mulesoft.org/schema/mule/core"
                          xmlns:http="http://www.mulesoft.org/schema/mule/http">
                      <http:request-config name="Payments_Config">
                        <http:request-connection host="${billing.payments.host}" port="443" protocol="HTTPS"/>
                      </http:request-config>
                    </mule>
                    """);
            write(dir, "src/main/mule/billing.xml", """
                    <mule xmlns="http://www.mulesoft.org/schema/mule/core"
                          xmlns:http="http://www.mulesoft.org/schema/mule/http">
                      <flow name="get:\\payments\\(id):billing-exp-api-config">
                        <http:request method="GET" path="/payments/{id}" config-ref="Payments_Config"/>
                      </flow>
                    </mule>
                    """);

            MuleScan scan = MuleProjectScanner.scan(dir);
            var call = scan.endpoints().get(0).calls().get(0);

            assertEquals("payments-sys-api", call.api(), () -> "resolved API was " + call.api());
        } finally {
            deleteRecursively(dir);
        }
    }

    private static void write(java.nio.file.Path base, String rel, String content) throws java.io.IOException {
        java.nio.file.Path p = base.resolve(rel);
        java.nio.file.Files.createDirectories(p.getParent());
        java.nio.file.Files.writeString(p, content);
    }

    private static void deleteRecursively(java.nio.file.Path dir) throws java.io.IOException {
        try (var walk = java.nio.file.Files.walk(dir)) {
            walk.sorted(java.util.Comparator.reverseOrder()).forEach(p -> {
                try {
                    java.nio.file.Files.deleteIfExists(p);
                } catch (java.io.IOException ignored) {
                }
            });
        }
    }

    @Test
    void detectsBackendEndSystemsAsProducers() throws java.io.IOException {
        java.nio.file.Path dir = java.nio.file.Files.createTempDirectory("apiguard-backend-");
        try {
            write(dir, "pom.xml", """
                    <project xmlns="http://maven.apache.org/POM/4.0.0">
                      <modelVersion>4.0.0</modelVersion>
                      <groupId>com.acme</groupId><artifactId>accounts-sys-api</artifactId><version>1.0.0</version>
                    </project>
                    """);
            write(dir, "src/main/mule/accounts.xml", """
                    <mule xmlns="http://www.mulesoft.org/schema/mule/core"
                          xmlns:db="http://www.mulesoft.org/schema/mule/db"
                          xmlns:salesforce="http://www.mulesoft.org/schema/mule/salesforce">
                      <flow name="get:\\accounts\\(id):accounts-sys-api-config">
                        <db:select config-ref="Accounts_DB">
                          <db:sql>SELECT * FROM accounts WHERE id = :id</db:sql>
                        </db:select>
                        <salesforce:query config-ref="SFDC_Config">
                          <salesforce:salesforce-query>SELECT Id FROM Account</salesforce:salesforce-query>
                        </salesforce:query>
                      </flow>
                    </mule>
                    """);

            MuleScan scan = MuleProjectScanner.scan(dir);
            var calls = scan.endpoints().get(0).calls();

            assertTrue(calls.stream().anyMatch(c -> c.api().equals("Database")), () -> "calls: " + calls);
            assertTrue(calls.stream().anyMatch(c -> c.api().equals("Salesforce")), () -> "calls: " + calls);

            assertEquals(2, calls.size(), () -> "exactly one op per connector: " + calls);
        } finally {
            deleteRecursively(dir);
        }
    }

    @Test
    void parsesApikitFlowNames() {
        assertEquals("GET", MuleProjectScanner.parseEndpointName("get:\\orders\\(orderId):cfg").method());
        assertEquals("/orders/{orderId}", MuleProjectScanner.parseEndpointName("get:\\orders\\(orderId):cfg").path());
        assertEquals("/orders", MuleProjectScanner.parseEndpointName("post:\\orders:application\\json:cfg").path());

        assertEquals(null, MuleProjectScanner.parseEndpointName("some-private-subflow"));
    }

    @Test
    void producesConsumerManifestForResolver() {
        MuleScan scan = MuleProjectScanner.scan(sampleProject());
        DependencyManifest m = scan.toManifest();
        assertEquals("orders-exp-api", m.consumer);
        assertNotNull(m.dependsOn);

        var processDep = m.dependsOn.stream().filter(d -> d.api.equals("orders-process-api")).findFirst().orElseThrow();
        assertTrue(processDep.endpoints.stream().anyMatch(e -> e.path.equals("GET /orders/{orderId}")));
    }

    @Test
    void datweaveGivesFieldLevelDependencies() {
        MuleScan scan = MuleProjectScanner.scan(sampleProject());
        DependencyManifest m = scan.toManifest();

        var processDep = m.dependsOn.stream().filter(d -> d.api.equals("orders-process-api")).findFirst().orElseThrow();
        var getById = processDep.endpoints.stream().filter(e -> e.path.equals("GET /orders/{orderId}")).findFirst().orElseThrow();
        assertTrue(getById.fields.contains("customerId"), () -> "fields: " + getById.fields);
        assertTrue(getById.fields.contains("status"));
        assertTrue(getById.fields.contains("orderId"));
    }

    @Test
    void attachesOwnerMetadataFromOwnerFile() {
        MuleScan scan = MuleProjectScanner.scan(sampleProject());
        assertEquals("orders-experience", scan.owner().ownerTeam());
        assertTrue(scan.owner().reviewers().contains("gh:dan"));

        DependencyManifest m = scan.toManifest();
        assertEquals("orders-experience", m.ownerTeam);
        assertEquals("#orders-exp-alerts", m.slackChannel);
    }
}
