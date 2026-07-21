package com.apiguard.server.web;

import com.apiguard.server.anypoint.AnypointClient;
import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.anypoint.AnypointSyncService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AnypointController {

    private final AnypointClient client;
    private final AnypointCredentials creds;
    private final AnypointSyncService sync;

    public AnypointController(AnypointClient client, AnypointCredentials creds, AnypointSyncService sync) {
        this.client = client;
        this.creds = creds;
        this.sync = sync;
    }

    public record StatusDto(boolean configured, String orgId, String environment, String baseUrl) {
    }

    public record ConfigRequest(
            @NotBlank String clientId,
            @NotBlank String clientSecret,
            String orgId,
            String environment) {
    }

    @GetMapping("/api/anypoint/status")
    public StatusDto status() {
        return new StatusDto(creds.isConfigured(), creds.orgId(), creds.environment(), client.baseUrl());
    }

    @PostMapping("/api/anypoint/config")
    public StatusDto configure(@RequestBody ConfigRequest req) {
        creds.update(req.clientId(), req.clientSecret(), req.orgId(), req.environment());
        return new StatusDto(creds.isConfigured(), creds.orgId(), creds.environment(), client.baseUrl());
    }

    @PostMapping("/api/anypoint/disconnect")
    public StatusDto disconnect() {
        creds.clear();
        return new StatusDto(false, creds.orgId(), creds.environment(), client.baseUrl());
    }

    @PostMapping("/api/anypoint/sync")
    public AnypointSyncService.SyncResult sync() {
        return sync.sync();
    }

    @GetMapping("/api/anypoint/links")
    public LinksDto links(@org.springframework.web.bind.annotation.RequestParam(required = false) String api) {
        String base = client.baseUrl();
        String org = creds.orgId();
        if (base == null || org == null || org.isBlank()) {
            return new LinksDto(null, null, null);
        }
        String encApi = api == null || api.isBlank()
                ? null
                : java.net.URLEncoder.encode(api, java.nio.charset.StandardCharsets.UTF_8);
        String exchange = encApi == null
                ? base + "/exchange/" + org + "/"
                : base + "/exchange/" + org + "/" + encApi + "/";
        String apiManager = encApi == null
                ? base + "/apiplatform/" + org + "/#/apis/all"
                : base + "/apiplatform/" + org + "/#/apis/all?search=" + encApi;
        String designCenter = base + "/designcenter/";
        return new LinksDto(exchange, apiManager, designCenter);
    }

    public record LinksDto(String exchange, String apiManager, String designCenter) {
    }
}
