package com.apiguard.server.web;

import com.apiguard.server.anypoint.AnypointClient;
import com.apiguard.server.anypoint.AnypointCredentials;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AnypointController {

    private final AnypointClient client;
    private final AnypointCredentials creds;

    public AnypointController(AnypointClient client, AnypointCredentials creds) {
        this.client = client;
        this.creds = creds;
    }

    @GetMapping("/api/anypoint/links")
    public LinksDto links(@RequestParam(required = false) String api) {
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
