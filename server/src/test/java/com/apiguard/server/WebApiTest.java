package com.apiguard.server;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class WebApiTest {

    @Autowired
    MockMvc mvc;
    @Autowired
    ObjectMapper json;

    private static final String V1 = "openapi: 3.0.3\ninfo: {title: T, version: 1.0.0}\n"
            + "paths:\n  /o/{id}:\n    get:\n      parameters: [{name: id, in: path, required: true, schema: {type: string}}]\n"
            + "      responses:\n        '200':\n          description: ok\n          content:\n            application/json:\n"
            + "              schema:\n                type: object\n                properties:\n                  id: {type: string}\n                  customerId: {type: string}\n";
    private static final String V2 = "openapi: 3.0.3\ninfo: {title: T, version: 2.0.0}\n"
            + "paths:\n  /o/{id}:\n    get:\n      parameters: [{name: id, in: path, required: true, schema: {type: string}}]\n"
            + "      responses:\n        '200':\n          description: ok\n          content:\n            application/json:\n"
            + "              schema:\n                type: object\n                properties:\n                  id: {type: string}\n";

    @Test
    void ingestManifestThenAnalyzeThenReadGraph() throws Exception {

        String manifestYaml = """
                consumer: web-x
                owner_team: team-x
                reviewers: [ "gh:dana" ]
                depends_on:
                  - api: o-api
                    endpoints:
                      - path: "GET /o/{id}"
                        fields: [ "customerId" ]
                """;
        mvc.perform(post("/api/manifests/dependency").contentType(MediaType.TEXT_PLAIN).content(manifestYaml))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.consumer").value("web-x"));

        String body = json.writeValueAsString(Map.of(
                "api", "o-api", "repo", "acme/o-api",
                "oldSpec", V1, "newSpec", V2,
                "fromLabel", "v1", "toLabel", "v2", "notifyPr", false));
        mvc.perform(post("/api/analyze").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.summary.breaking").value(1))
                .andExpect(jsonPath("$.summary.impactedConsumers").value(1))
                .andExpect(jsonPath("$.changelog").value(org.hamcrest.Matchers.containsString("Breaking")))
                .andExpect(jsonPath("$.impacts[0].downstream[0].consumer").value("web-x"));

        mvc.perform(get("/api/graph"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nodes[?(@.layer=='APP')].label").value(org.hamcrest.Matchers.hasItem("web-x")));
        mvc.perform(get("/api/changelog?api=o-api"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].versionLabel").value("v2"));
        mvc.perform(get("/api/apis/o-api/changes"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].classification").value("BREAKING"));

        mvc.perform(get("/api/apis/o-api/spec/latest"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.versionLabel").value("v2"))
                .andExpect(jsonPath("$.spec").value(org.hamcrest.Matchers.containsString("version: 2.0.0")));
        mvc.perform(get("/api/apis/no-such-api/spec/latest"))
                .andExpect(status().isNoContent());

        mvc.perform(get("/api/explorer").param("api", "o-api").param("endpoint", "GET /o/{id}").param("field", "customerId"))
                .andExpect(status().isOk())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("web-x")));
    }

    @Test
    void badSpecReturns400() throws Exception {
        String body = json.writeValueAsString(Map.of(
                "api", "x", "oldSpec", "not a spec [", "newSpec", "also bad ["));
        mvc.perform(post("/api/analyze").contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").exists());
    }

    @Test
    void malformedJsonBodyReturns400WithErrorField() throws Exception {
        mvc.perform(post("/api/analyze").contentType(MediaType.APPLICATION_JSON).content("{ not valid json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("Malformed request body."));
    }

    @Test
    void healthAndVersionAreExposed() throws Exception {
        mvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.name").value("Wakegraph"))
                .andExpect(jsonPath("$.version").value("0.1.0"))
                .andExpect(jsonPath("$.uptimeSeconds").exists())
                .andExpect(jsonPath("$.authRequired").value(false));
        mvc.perform(get("/api/version"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Wakegraph"))
                .andExpect(jsonPath("$.java").exists());
    }
}
