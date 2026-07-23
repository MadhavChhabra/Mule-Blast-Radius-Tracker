package com.apiguard.server;

import com.apiguard.core.mule.MuleProjectScanner;
import com.apiguard.server.service.ScanService;
import org.hamcrest.Matchers;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
class ScanSpecIngestTest {

    @Autowired
    ScanService scanService;
    @Autowired
    MockMvc mvc;

    @Test
    void scanCapturesApiSpecAndServesItViaLatestEndpoint() throws Exception {
        Path dir = Files.createTempDirectory("wg-scan-spec-");
        try {
            write(dir, "pom.xml", """
                    <project xmlns="http://maven.apache.org/POM/4.0.0">
                      <modelVersion>4.0.0</modelVersion>
                      <groupId>com.acme</groupId><artifactId>spectest-exp-api</artifactId><version>2.3.0</version>
                    </project>
                    """);
            write(dir, "src/main/mule/app.xml", """
                    <mule xmlns="http://www.mulesoft.org/schema/mule/core"
                          xmlns:apikit="http://www.mulesoft.org/schema/mule/mule-apikit">
                      <apikit:config name="spectest-exp-api-config" api="api/spectest.raml"/>
                    </mule>
                    """);
            write(dir, "src/main/resources/api/spectest.raml", """
                    #%RAML 1.0
                    title: Spec Test API
                    version: v1
                    mediaType: application/json
                    /widgets:
                      get:
                        responses:
                          200:
                            body:
                              application/json:
                                type: object
                                properties:
                                  id: string
                    """);

            scanService.ingest(MuleProjectScanner.scanAll(dir));

            mvc.perform(get("/api/apis/spectest-exp-api/spec/latest"))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.versionLabel").value("2.3.0"))
                    .andExpect(jsonPath("$.spec").value(Matchers.containsString("openapi:")))
                    .andExpect(jsonPath("$.spec").value(Matchers.containsString("/widgets")));
        } finally {
            deleteRecursively(dir);
        }
    }

    private static void write(Path base, String rel, String content) throws IOException {
        Path p = base.resolve(rel);
        Files.createDirectories(p.getParent());
        Files.writeString(p, content);
    }

    private static void deleteRecursively(Path dir) throws IOException {
        try (Stream<Path> walk = Files.walk(dir)) {
            walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException ignored) {
                }
            });
        }
    }
}
