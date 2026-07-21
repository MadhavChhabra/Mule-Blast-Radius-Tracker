package com.apiguard.server.web;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.info.BuildProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
public class HealthController {

    private static final String NAME = "Wakegraph";

    private final String fallbackVersion;
    private final boolean authRequired;
    private final ObjectProvider<BuildProperties> buildProperties;
    private final Instant startedAt = Instant.now();

    public HealthController(@Value("${apiguard.version:0.1.0}") String fallbackVersion,
                            @Value("${apiguard.security.api-key:${APIGUARD_API_KEY_SERVER:}}") String apiKey,
                            ObjectProvider<BuildProperties> buildProperties) {
        this.fallbackVersion = fallbackVersion;
        this.authRequired = apiKey != null && !apiKey.isBlank();
        this.buildProperties = buildProperties;
    }

    private String resolveVersion() {
        BuildProperties bp = buildProperties.getIfAvailable();
        return bp != null && bp.getVersion() != null ? bp.getVersion() : fallbackVersion;
    }

    @GetMapping("/api/health")
    public Map<String, Object> health() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("status", "UP");
        body.put("name", NAME);
        body.put("version", resolveVersion());
        body.put("uptimeSeconds", Duration.between(startedAt, Instant.now()).getSeconds());
        body.put("authRequired", authRequired);
        return body;
    }

    @GetMapping("/api/version")
    public Map<String, Object> version() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", NAME);
        body.put("version", resolveVersion());
        body.put("java", System.getProperty("java.version"));
        BuildProperties bp = buildProperties.getIfAvailable();
        if (bp != null && bp.getTime() != null) {
            body.put("builtAt", bp.getTime().toString());
        }
        return body;
    }
}
