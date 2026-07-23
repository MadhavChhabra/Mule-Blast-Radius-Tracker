package com.apiguard.cli;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;

class CheckCommandTest {

    private static OpenAPI withTitle(String title) {
        OpenAPI api = new OpenAPI();
        if (title != null) {
            api.setInfo(new Info().title(title));
        }
        return api;
    }

    @Test
    void infersSlugFromSpecTitle() {
        assertEquals("orders-experience-api",
                CheckCommand.inferApiName(withTitle("Orders Experience API"), Path.of("openapi.yaml")));
    }

    @Test
    void fallsBackToFileStemWhenNoTitle() {
        assertEquals("orders-exp-api",
                CheckCommand.inferApiName(withTitle(null), Path.of("specs/orders-exp-api.raml")));
    }

    @Test
    void fallsBackToApiWhenNothingUsable() {
        assertEquals("api", CheckCommand.inferApiName(withTitle("  "), Path.of("+++.json")));
    }
}
