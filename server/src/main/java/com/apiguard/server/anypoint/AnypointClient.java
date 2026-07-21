package com.apiguard.server.anypoint;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Supplier;

@Component
public class AnypointClient {

    private static final Logger log = LoggerFactory.getLogger(AnypointClient.class);

    private final AnypointCredentials creds;
    private final RestClient http;
    private final String baseUrl;

    private String cachedToken;
    private Instant tokenExpiry = Instant.EPOCH;

    private static final int MAX_RETRIES = 5;
    private final int maxRetries;
    private final long minIntervalNanos;
    private final Object throttleLock = new Object();
    private long nextAllowedNanos = System.nanoTime();

    private final AtomicBoolean rateLimited = new AtomicBoolean(false);

    public AnypointClient(
            @Value("${apiguard.anypoint.base-url:https://anypoint.mulesoft.com}") String baseUrl,
            @Value("${apiguard.anypoint.max-requests-per-second:16}") int maxRps,
            @Value("${apiguard.anypoint.max-retries:5}") int maxRetries,
            AnypointCredentials creds) {
        this.creds = creds;
        this.baseUrl = baseUrl;
        this.maxRetries = maxRetries > 0 ? maxRetries : MAX_RETRIES;
        this.minIntervalNanos = 1_000_000_000L / Math.max(1, maxRps);

        org.springframework.http.client.SimpleClientHttpRequestFactory rf =
                new org.springframework.http.client.SimpleClientHttpRequestFactory();
        rf.setConnectTimeout(10_000);
        rf.setReadTimeout(30_000);
        this.http = RestClient.builder().baseUrl(baseUrl).requestFactory(rf).build();

        creds.setOnChange(this::invalidate);
    }

    public synchronized void invalidate() {
        cachedToken = null;
        tokenExpiry = Instant.EPOCH;
    }

    public String baseUrl() {
        return baseUrl;
    }

    public boolean isEnabled() {
        return creds.isConfigured();
    }

    public synchronized String token() {
        if (cachedToken != null && Instant.now().isBefore(tokenExpiry)) {
            return cachedToken;
        }
        if (!creds.isConfigured()) {
            throw new AnypointException("Anypoint credentials are not set.");
        }
        @SuppressWarnings("unchecked")
        Map<String, Object> resp = withRetry(() -> http.post()
                .uri("/accounts/api/v2/oauth2/token")
                .body(Map.of("grant_type", "client_credentials",
                        "client_id", creds.clientId(), "client_secret", creds.clientSecret()))
                .retrieve()
                .body(Map.class));
        if (resp == null || resp.get("access_token") == null) {
            throw new AnypointException("Anypoint token request returned no access_token");
        }
        cachedToken = resp.get("access_token").toString();
        long expiresIn = resp.get("expires_in") instanceof Number n ? n.longValue() : 3000;
        tokenExpiry = Instant.now().plusSeconds(Math.max(60, expiresIn - 60));
        return cachedToken;
    }

    @SuppressWarnings("unchecked")
    public String defaultOrgId() {
        Map<String, Object> me = get("/accounts/api/me", Map.class);
        if (me == null) {
            throw new AnypointException("Could not read /accounts/api/me");
        }
        Object user = me.get("user");
        if (user instanceof Map<?, ?> u) {
            Object org = u.get("organization");
            if (org instanceof Map<?, ?> o && o.get("id") != null) {
                return o.get("id").toString();
            }
            Object orgId = u.get("organizationId");
            if (orgId != null) {
                return orgId.toString();
            }
        }
        throw new AnypointException("Could not determine default org id from /accounts/api/me");
    }

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> environments(String orgId) {
        Map<String, Object> resp = get("/accounts/api/organizations/" + orgId + "/environments", Map.class);
        List<Map<String, Object>> out = new ArrayList<>();
        if (resp != null && resp.get("data") instanceof List<?> data) {
            for (Object o : data) {
                if (o instanceof Map<?, ?> m) {
                    out.add((Map<String, Object>) m);
                }
            }
        }
        return out;
    }

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> apis(String orgId, String envId) {
        Map<String, Object> resp = get(
                "/apimanager/api/v1/organizations/" + orgId + "/environments/" + envId + "/apis", Map.class);
        List<Map<String, Object>> out = new ArrayList<>();
        if (resp == null) {
            return out;
        }
        if (resp.get("assets") instanceof List<?> assets) {
            for (Object a : assets) {
                if (a instanceof Map<?, ?> asset && asset.get("apis") instanceof List<?> apis) {
                    String assetId = str(asset.get("assetId"));
                    for (Object api : apis) {
                        if (api instanceof Map<?, ?> apiMap) {
                            Map<String, Object> m = new java.util.HashMap<>((Map<String, Object>) apiMap);
                            m.putIfAbsent("assetId", assetId);
                            out.add(m);
                        }
                    }
                }
            }
        } else if (resp.get("apis") instanceof List<?> apis) {
            for (Object api : apis) {
                if (api instanceof Map<?, ?> apiMap) {
                    out.add((Map<String, Object>) apiMap);
                }
            }
        }
        return out;
    }

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> contracts(String orgId, String envId, String apiInstanceId) {
        Map<String, Object> resp = get("/apimanager/api/v1/organizations/" + orgId
                + "/environments/" + envId + "/apis/" + apiInstanceId + "/contracts", Map.class);
        List<Map<String, Object>> out = new ArrayList<>();
        if (resp != null && resp.get("contracts") instanceof List<?> contracts) {
            for (Object c : contracts) {
                if (c instanceof Map<?, ?> m) {
                    out.add((Map<String, Object>) m);
                }
            }
        }
        return out;
    }

    private static final int EXCHANGE_PAGE = 250;
    private static final int EXCHANGE_MAX_PAGES = 40;

    @SuppressWarnings("unchecked")
    public List<Map<String, Object>> exchangeAssets(String orgId) {

        java.util.LinkedHashMap<String, Map<String, Object>> byAsset = new java.util.LinkedHashMap<>();
        for (int page = 0; page < EXCHANGE_MAX_PAGES; page++) {
            List<?> raw = get("/exchange/api/v2/assets?organizationId=" + orgId
                    + "&types=rest-api&types=http-api&types=rest-api-spec&types=soap-api"
                    + "&limit=" + EXCHANGE_PAGE + "&offset=" + (page * EXCHANGE_PAGE), List.class);
            if (raw == null || raw.isEmpty()) {
                break;
            }
            for (Object o : raw) {
                if (o instanceof Map<?, ?> m) {
                    Map<String, Object> asset = (Map<String, Object>) m;
                    String key = str(asset.get("groupId")) + ":" + str(asset.get("assetId"));
                    byAsset.putIfAbsent(key, asset);
                }
            }
            if (raw.size() < EXCHANGE_PAGE) {
                break;
            }
        }
        return new ArrayList<>(byAsset.values());
    }

    public record ExchangeDep(String assetId, String name) {
    }

    @SuppressWarnings("unchecked")
    public List<ExchangeDep> exchangeAssetDependencies(String groupId, String assetId, String version) {
        Map<String, Object> asset = get("/exchange/api/v2/assets/" + groupId + "/" + assetId + "/" + version, Map.class);
        List<ExchangeDep> deps = new ArrayList<>();
        if (asset != null && asset.get("dependencies") instanceof List<?> list) {
            for (Object d : list) {
                if (d instanceof Map<?, ?> dm && dm.get("assetId") != null) {
                    deps.add(new ExchangeDep(dm.get("assetId").toString(), str(dm.get("name"))));
                }
            }
        }
        return deps;
    }

    private <T> T get(String uri, Class<T> type) {
        return withRetry(() -> http.get().uri(uri).headers(this::auth).retrieve().body(type));
    }

    private void auth(HttpHeaders headers) {
        headers.setBearerAuth(token());
        headers.set("Accept", "application/json");
    }

    public boolean wasRateLimited() {
        return rateLimited.get();
    }

    public void resetRateLimitFlag() {
        rateLimited.set(false);
    }

    private void throttle() {
        long waitNanos;
        synchronized (throttleLock) {
            long now = System.nanoTime();
            long start = Math.max(now, nextAllowedNanos);
            nextAllowedNanos = start + minIntervalNanos;
            waitNanos = start - now;
        }
        if (waitNanos > 0) {
            try {
                Thread.sleep(waitNanos / 1_000_000L, (int) (waitNanos % 1_000_000L));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    private <T> T withRetry(Supplier<T> call) {
        int attempt = 0;
        while (true) {
            throttle();
            try {
                return call.get();
            } catch (HttpClientErrorException.TooManyRequests e) {
                rateLimited.set(true);
                if (attempt >= maxRetries) {
                    throw e;
                }
                long waitMs = retryAfterMillis(e, attempt);
                log.warn("Anypoint rate limit hit; backing off {} ms (retry {}/{})", waitMs, attempt + 1, maxRetries);
                sleepMs(waitMs);
                attempt++;
            }
        }
    }

    private static long retryAfterMillis(HttpClientErrorException e, int attempt) {
        HttpHeaders h = e.getResponseHeaders();
        if (h != null) {
            Long fromRetryAfter = parseSeconds(h.getFirst("Retry-After"));
            if (fromRetryAfter != null) {
                return clampWait(fromRetryAfter * 1000L);
            }
            Long reset = parseSeconds(h.getFirst("x-ratelimit-reset"));
            if (reset != null) {
                long secs = reset - Instant.now().getEpochSecond();
                if (secs > 0 && secs < 300) {
                    return clampWait(secs * 1000L);
                }
            }
        }

        return clampWait(1000L * (1L << Math.min(attempt + 1, 5)));
    }

    private static Long parseSeconds(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return Long.parseLong(value.trim());
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    private static long clampWait(long ms) {
        return Math.max(500L, Math.min(ms, 30_000L));
    }

    private static void sleepMs(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    static String str(Object o) {
        return o == null ? null : o.toString();
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    public static final class AnypointException extends RuntimeException {
        public AnypointException(String message) {
            super(message);
        }
    }
}
