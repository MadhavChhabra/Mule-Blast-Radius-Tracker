package com.apiguard.core.spec;

import io.swagger.v3.oas.models.OpenAPI;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

class SpecLoaderTest {

    @Test
    void loadsYaml() {
        OpenAPI api = SpecLoader.loadString("""
                openapi: 3.0.3
                info: { title: T, version: 1.0.0 }
                paths:
                  /ping:
                    get:
                      responses:
                        '200': { description: ok }
                """);
        assertNotNull(api.getPaths().get("/ping"));
    }

    @Test
    void loadsJson() {
        OpenAPI api = SpecLoader.loadString("""
                {"openapi":"3.0.3","info":{"title":"T","version":"1.0.0"},
                 "paths":{"/ping":{"get":{"responses":{"200":{"description":"ok"}}}}}}
                """);
        assertNotNull(api.getPaths().get("/ping"));
    }

    @Test
    void resolvesRefsFully() {
        OpenAPI api = SpecLoader.loadString("""
                openapi: 3.0.3
                info: { title: T, version: 1.0.0 }
                paths:
                  /o:
                    get:
                      responses:
                        '200':
                          description: ok
                          content:
                            application/json:
                              schema: { $ref: '#/components/schemas/O' }
                components:
                  schemas:
                    O:
                      type: object
                      properties:
                        id: { type: string }
                """);
        io.swagger.v3.oas.models.media.Schema<?> schema = api.getPaths().get("/o").getGet()
                .getResponses().get("200").getContent().get("application/json").getSchema();
        // resolveFully inlines the $ref so properties are directly reachable.
        assertNotNull(schema.getProperties());
        io.swagger.v3.oas.models.media.Schema<?> idSchema =
                (io.swagger.v3.oas.models.media.Schema<?>) schema.getProperties().get("id");
        assertEquals("string", idSchema.getType());
    }

    @Test
    void throwsOnGarbage() {
        assertThrows(SpecLoader.SpecLoadException.class,
                () -> SpecLoader.loadString("this is not a spec at all: ["));
    }
}
