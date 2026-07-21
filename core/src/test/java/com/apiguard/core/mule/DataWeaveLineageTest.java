package com.apiguard.core.mule;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class DataWeaveLineageTest {

    @Test
    void extractsPayloadFieldReferences() {
        String dw = """
                %dw 2.0
                output application/json
                ---
                {
                  id: payload.orderId,
                  customer: payload.customerId,
                  state: payload.status,
                  nested: payload.customer.email,
                  indexed: payload.items[0].sku
                }
                """;
        List<String> fields = DataWeaveLineage.referencedFields(dw);
        assertTrue(fields.contains("orderId"));
        assertTrue(fields.contains("customerId"));
        assertTrue(fields.contains("status"));
        assertTrue(fields.contains("customer"));
        assertTrue(fields.contains("email"));
        assertTrue(fields.contains("items"));
        assertTrue(fields.contains("sku"));
    }

    @Test
    void ignoresNonPayloadText() {
        assertEquals(List.of(), DataWeaveLineage.referencedFields("just some text, vars.foo, attributes.bar"));
    }

    @Test
    void fieldSitesUnderWalksDwlFilesAndReportsSourcePaths(@TempDir Path root) throws Exception {
        Path a = root.resolve("dwl/charge.dwl");
        Path b = root.resolve("dwl/audit/invoice.dwl");
        Files.createDirectories(a.getParent());
        Files.createDirectories(b.getParent());
        Files.writeString(a, """
                %dw 2.0
                output application/json
                ---
                { total: payload.amount, id: payload.orderId }
                """);
        Files.writeString(b, """
                %dw 2.0
                output application/json
                ---
                { customer: payload.customerId, order: payload.orderId }
                """);

        Map<String, List<String>> sites = DataWeaveLineage.fieldSitesUnder(root);

        assertTrue(sites.containsKey("orderId"));
        assertEquals(2, sites.get("orderId").size(), () -> "orderId is used in both files: " + sites.get("orderId"));
        assertTrue(sites.get("orderId").contains("dwl/charge.dwl"));
        assertTrue(sites.get("orderId").contains("dwl/audit/invoice.dwl"));
        assertEquals(List.of("dwl/charge.dwl"), sites.get("amount"));
    }

    @Test
    void fieldSitesUnderMissingRootReturnsEmpty() {
        assertTrue(DataWeaveLineage.fieldSitesUnder(Path.of("/definitely/does/not/exist")).isEmpty());
    }
}
