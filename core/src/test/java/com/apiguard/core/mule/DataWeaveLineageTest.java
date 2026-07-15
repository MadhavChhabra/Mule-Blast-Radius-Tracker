package com.apiguard.core.mule;

import org.junit.jupiter.api.Test;

import java.util.List;

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
}
