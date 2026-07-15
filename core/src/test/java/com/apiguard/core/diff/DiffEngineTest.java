package com.apiguard.core.diff;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.List;

import static com.apiguard.core.diff.DiffTestSupport.assertHasKind;
import static com.apiguard.core.diff.DiffTestSupport.assertNoBreaking;
import static com.apiguard.core.diff.DiffTestSupport.diff;
import static com.apiguard.core.diff.DiffTestSupport.single;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * One test per breaking-change rule from build brief §5, each using a minimal before/after
 * spec pair. These tests are the specification of the engine's behaviour — read them to
 * understand exactly what APIGuard classifies and why.
 */
class DiffEngineTest {

    // A reusable GET /orders/{id} operation body with a response object.
    private static String getOrders(String responseProps) {
        return """
                paths:
                  /orders/{id}:
                    get:
                      parameters:
                        - name: id
                          in: path
                          required: true
                          schema: { type: string }
                      responses:
                        '200':
                          description: ok
                          content:
                            application/json:
                              schema:
                                type: object
                                properties:
                """ + responseProps.indent(20);
    }

    @Nested
    @DisplayName("Endpoints & operations")
    class Endpoints {
        @Test
        void endpointRemovedIsBreaking() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n",
                    "paths: {}\n");
            assertHasKind(changes, ChangeKind.ENDPOINT_REMOVED, Classification.BREAKING);
        }

        @Test
        void operationRemovedIsBreaking() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n    post:\n      responses:\n        '201': { description: created }\n",
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.OPERATION_REMOVED, Classification.BREAKING);
        }

        @Test
        void newEndpointIsAdditive() {
            var changes = diff(
                    "paths: {}\n",
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.ENDPOINT_ADDED, Classification.ADDITIVE);
            assertNoBreaking(changes);
        }
    }

    @Nested
    @DisplayName("Response fields (what the server returns)")
    class ResponseFields {
        @Test
        void responseFieldRemovedIsBreaking() {
            var changes = diff(
                    getOrders("id: { type: string }\ncustomerId: { type: string }\n"),
                    getOrders("id: { type: string }\n"));
            var c = single(changes, ChangeKind.RESPONSE_FIELD_REMOVED);
            assertEquals(Classification.BREAKING, c.classification());
            assertEquals("customerId", c.field());
        }

        @Test
        void newResponseFieldIsAdditive() {
            var changes = diff(
                    getOrders("id: { type: string }\n"),
                    getOrders("id: { type: string }\ncustomerId: { type: string }\n"));
            assertHasKind(changes, ChangeKind.RESPONSE_FIELD_ADDED, Classification.ADDITIVE);
            assertNoBreaking(changes);
        }

        @Test
        void responseFieldTypeChangeIsBreaking() {
            var changes = diff(
                    getOrders("total: { type: integer }\n"),
                    getOrders("total: { type: string }\n"));
            assertHasKind(changes, ChangeKind.FIELD_TYPE_CHANGED, Classification.BREAKING);
        }

        @Test
        void responseFieldBecomingNullableIsBreaking() {
            var changes = diff(
                    getOrders("total: { type: integer }\n"),
                    getOrders("total: { type: integer, nullable: true }\n"));
            assertHasKind(changes, ChangeKind.RESPONSE_FIELD_NULLABLE_ADDED, Classification.BREAKING);
        }
    }

    @Nested
    @DisplayName("Request fields & parameters (what the server accepts)")
    class RequestFields {
        private static String postOrders(String requestProps, String requiredList) {
            // requestProps is one property per line; indent each to sit under `properties:` (14 spaces).
            StringBuilder props = new StringBuilder();
            for (String line : requestProps.strip().split("\n")) {
                props.append("                ").append(line.strip()).append('\n'); // 16 spaces: under properties:
            }
            return "paths:\n"
                    + "  /orders:\n"
                    + "    post:\n"
                    + "      requestBody:\n"
                    + "        content:\n"
                    + "          application/json:\n"
                    + "            schema:\n"
                    + "              type: object\n"
                    + "              required: " + requiredList + "\n"
                    + "              properties:\n"
                    + props
                    + "      responses:\n"
                    + "        '201': { description: created }\n";
        }

        @Test
        void newRequiredRequestFieldIsBreaking() {
            var changes = diff(
                    postOrders("amount: { type: integer }\n", "[amount]"),
                    postOrders("amount: { type: integer }\ncurrency: { type: string }\n", "[amount, currency]"));
            assertHasKind(changes, ChangeKind.REQUEST_FIELD_ADDED_REQUIRED, Classification.BREAKING);
        }

        @Test
        void newOptionalRequestFieldIsAdditive() {
            var changes = diff(
                    postOrders("amount: { type: integer }\n", "[amount]"),
                    postOrders("amount: { type: integer }\ncouponCode: { type: string }\n", "[amount]"));
            assertHasKind(changes, ChangeKind.REQUEST_FIELD_ADDED_OPTIONAL, Classification.ADDITIVE);
            assertNoBreaking(changes);
        }

        @Test
        void existingRequestFieldMadeRequiredIsBreaking() {
            var changes = diff(
                    postOrders("amount: { type: integer }\ncoupon: { type: string }\n", "[amount]"),
                    postOrders("amount: { type: integer }\ncoupon: { type: string }\n", "[amount, coupon]"));
            assertHasKind(changes, ChangeKind.REQUEST_FIELD_MADE_REQUIRED, Classification.BREAKING);
        }

        @Test
        void optionalParamAddedIsAdditive() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n",
                    "paths:\n  /orders:\n    get:\n      parameters:\n        - name: limit\n          in: query\n          required: false\n          schema: { type: integer }\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.PARAM_ADDED_OPTIONAL, Classification.ADDITIVE);
            assertNoBreaking(changes);
        }

        @Test
        void requiredParamAddedIsBreaking() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n",
                    "paths:\n  /orders:\n    get:\n      parameters:\n        - name: tenant\n          in: query\n          required: true\n          schema: { type: string }\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.PARAM_ADDED_REQUIRED, Classification.BREAKING);
        }

        @Test
        void optionalParamMadeRequiredIsBreaking() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      parameters:\n        - name: tenant\n          in: query\n          required: false\n          schema: { type: string }\n      responses:\n        '200': { description: ok }\n",
                    "paths:\n  /orders:\n    get:\n      parameters:\n        - name: tenant\n          in: query\n          required: true\n          schema: { type: string }\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.PARAM_MADE_REQUIRED, Classification.BREAKING);
        }

        @Test
        void requiredParamRemovedIsBreaking() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      parameters:\n        - name: tenant\n          in: query\n          required: true\n          schema: { type: string }\n      responses:\n        '200': { description: ok }\n",
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.PARAM_REMOVED, Classification.BREAKING);
        }
    }

    @Nested
    @DisplayName("Enum asymmetry (the detail that shows depth)")
    class Enums {
        private static String requestEnum(String values) {
            return """
                    paths:
                      /orders:
                        post:
                          requestBody:
                            content:
                              application/json:
                                schema:
                                  type: object
                                  properties:
                                    channel:
                                      type: string
                                      enum: %s
                          responses:
                            '201': { description: created }
                    """.formatted(values);
        }

        private static String responseEnum(String values) {
            return """
                    paths:
                      /orders/{id}:
                        get:
                          parameters:
                            - name: id
                              in: path
                              required: true
                              schema: { type: string }
                          responses:
                            '200':
                              description: ok
                              content:
                                application/json:
                                  schema:
                                    type: object
                                    properties:
                                      status:
                                        type: string
                                        enum: %s
                    """.formatted(values);
        }

        @Test
        void removingRequestEnumValueIsBreaking() {
            var changes = diff(requestEnum("[web, app, phone]"), requestEnum("[web, app]"));
            assertHasKind(changes, ChangeKind.REQUEST_ENUM_VALUE_REMOVED, Classification.BREAKING);
        }

        @Test
        void addingRequestEnumValueIsAdditive() {
            var changes = diff(requestEnum("[web, app]"), requestEnum("[web, app, phone]"));
            assertHasKind(changes, ChangeKind.REQUEST_ENUM_VALUE_ADDED, Classification.ADDITIVE);
            assertNoBreaking(changes);
        }

        @Test
        void addingResponseEnumValueIsBreaking() {
            var changes = diff(responseEnum("[open, closed]"), responseEnum("[open, closed, refunded]"));
            assertHasKind(changes, ChangeKind.RESPONSE_ENUM_VALUE_ADDED, Classification.BREAKING);
        }

        @Test
        void removingResponseEnumValueIsNonBreaking() {
            var changes = diff(responseEnum("[open, closed, refunded]"), responseEnum("[open, closed]"));
            assertHasKind(changes, ChangeKind.RESPONSE_ENUM_VALUE_REMOVED, Classification.NON_BREAKING);
            assertNoBreaking(changes);
        }
    }

    @Nested
    @DisplayName("Security & nested structures")
    class SecurityAndNesting {
        @Test
        void addingAuthIsBreaking() {
            var changes = diff(
                    "paths:\n  /orders:\n    get:\n      responses:\n        '200': { description: ok }\n",
                    "paths:\n  /orders:\n    get:\n      security:\n        - apiKey: []\n      responses:\n        '200': { description: ok }\n");
            assertHasKind(changes, ChangeKind.AUTH_TIGHTENED, Classification.BREAKING);
        }

        @Test
        void nestedResponseFieldRemovalIsBreaking() {
            String before = """
                    paths:
                      /orders/{id}:
                        get:
                          parameters:
                            - name: id
                              in: path
                              required: true
                              schema: { type: string }
                          responses:
                            '200':
                              description: ok
                              content:
                                application/json:
                                  schema:
                                    type: object
                                    properties:
                                      customer:
                                        type: object
                                        properties:
                                          id: { type: string }
                                          email: { type: string }
                    """;
            String after = before.replace("      email: { type: string }\n", "");
            var changes = diff(before, after);
            var c = single(changes, ChangeKind.RESPONSE_FIELD_REMOVED);
            assertEquals("email", c.field());
            assertTrue(c.jsonPointer().contains("customer"), "pointer should include the nested path");
        }

        @Test
        void arrayItemFieldTypeChangeIsBreaking() {
            String before = """
                    paths:
                      /orders:
                        get:
                          responses:
                            '200':
                              description: ok
                              content:
                                application/json:
                                  schema:
                                    type: array
                                    items:
                                      type: object
                                      properties:
                                        total: { type: integer }
                    """;
            String after = before.replace("total: { type: integer }", "total: { type: string }");
            var changes = diff(before, after);
            assertHasKind(changes, ChangeKind.FIELD_TYPE_CHANGED, Classification.BREAKING);
        }
    }

    @Test
    @DisplayName("Identical specs produce no changes")
    void identicalSpecsNoChanges() {
        String body = getOrders("id: { type: string }\ncustomerId: { type: string }\n");
        List<Change> changes = diff(body, body);
        assertTrue(changes.isEmpty(), () -> "Expected no changes but got: " + changes);
    }
}
