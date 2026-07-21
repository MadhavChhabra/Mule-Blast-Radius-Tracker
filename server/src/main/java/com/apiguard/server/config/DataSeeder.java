package com.apiguard.server.config;

import com.apiguard.core.blast.ManifestLoader;
import com.apiguard.server.service.AnalysisService;
import com.apiguard.server.service.ManifestService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;

import java.nio.charset.StandardCharsets;

@Configuration
@ConditionalOnProperty(name = "apiguard.seed.enabled", havingValue = "true", matchIfMissing = true)
public class DataSeeder {

    private static final Logger log = LoggerFactory.getLogger(DataSeeder.class);

    @Bean
    ApplicationRunner seed(ManifestService manifestService, AnalysisService analysisService) {
        return args -> {
            if (!manifestService.all().isEmpty()) {
                return;
            }
            log.info("Seeding demo API-led estate (apps → experience → process → system)...");

            manifestService.ingestDependency(ManifestLoader.loadDependency("""
                    consumer: web-checkout-app
                    owner_team: web-checkout
                    reviewers: [ "gh:alice", "gh:bob" ]
                    slack_channel: "#checkout-alerts"
                    depends_on:
                      - api: orders-exp-api
                        endpoints:
                          - path: "*"
                    """));
            manifestService.ingestDependency(ManifestLoader.loadDependency("""
                    consumer: mobile-app
                    owner_team: mobile
                    reviewers: [ "gh:dan" ]
                    depends_on:
                      - api: orders-exp-api
                        endpoints:
                          - path: "*"
                    """));

            manifestService.ingestDependency(ManifestLoader.loadDependency("""
                    consumer: orders-exp-api
                    owner_team: orders-experience
                    reviewers: [ "gh:erin" ]
                    slack_channel: "#orders-exp"
                    depends_on:
                      - api: orders-process-api
                        endpoints:
                          - path: "GET /orders/{id}"
                            fields: [ "customerId", "status", "amount" ]
                    """));

            manifestService.ingestDependency(ManifestLoader.loadDependency("""
                    consumer: orders-process-api
                    owner_team: orders-platform
                    reviewers: [ "gh:frank" ]
                    depends_on:
                      - api: customers-sys-api
                        endpoints:
                          - path: "GET /customers/{id}"
                            fields: [ "id", "email" ]
                      - api: inventory-sys-api
                        endpoints:
                          - path: "*"
                    """));

            manifestService.ingestSources(ManifestLoader.loadSources("""
                    api: orders-process-api
                    sources:
                      - endpoint: "GET /orders/{id}"
                        field: "customerId"
                        from: { api: customers-sys-api, endpoint: "GET /customers/{id}", field: "id" }
                    """));

            analysisService.analyze(new AnalysisService.AnalyzeCommand(
                    "orders-process-api", "acme/orders-process-api",
                    read("seed/openapi-v1.yaml"), read("seed/openapi-v2.yaml"),
                    "v1.0.0", "v2.0.0", null, false));

            log.info("Demo estate seeded.");
        };
    }

    private static String read(String path) {
        try {
            return new String(new ClassPathResource(path).getInputStream().readAllBytes(), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("Could not read seed resource " + path, e);
        }
    }
}
