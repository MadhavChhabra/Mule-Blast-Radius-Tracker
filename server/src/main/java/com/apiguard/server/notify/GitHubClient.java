package com.apiguard.server.notify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Base64;
import java.util.List;
import java.util.Map;

@Component
public class GitHubClient {

    private static final Logger log = LoggerFactory.getLogger(GitHubClient.class);

    private final String token;
    private final RestClient http;

    public GitHubClient(@Value("${apiguard.github.token:}") String token,
                        @Value("${apiguard.github.api-url:https://api.github.com}") String apiUrl) {
        this.token = token;
        this.http = RestClient.builder().baseUrl(apiUrl).build();
    }

    public boolean isEnabled() {
        return token != null && !token.isBlank();
    }

    public void requestReviewers(String repo, int prNumber, List<String> reviewers) {
        if (reviewers == null || reviewers.isEmpty()) {
            return;
        }
        if (!isEnabled()) {
            log.info("[github disabled] would request reviewers {} on {}#{}", reviewers, repo, prNumber);
            return;
        }
        try {
            http.post().uri("/repos/{repo}/pulls/{n}/requested_reviewers", repo, prNumber)
                    .headers(this::auth)
                    .body(Map.of("reviewers", reviewers))
                    .retrieve()
                    .toBodilessEntity();
        } catch (Exception e) {
            log.warn("requestReviewers failed for {}#{}: {}", repo, prNumber, e.getMessage());
        }
    }

    public void comment(String repo, int prNumber, String markdown) {
        if (!isEnabled()) {
            log.info("[github disabled] would comment on {}#{}:\n{}", repo, prNumber, markdown);
            return;
        }
        try {
            http.post().uri("/repos/{repo}/issues/{n}/comments", repo, prNumber)
                    .headers(this::auth)
                    .body(Map.of("body", markdown))
                    .retrieve()
                    .toBodilessEntity();
        } catch (Exception e) {
            log.warn("comment failed for {}#{}: {}", repo, prNumber, e.getMessage());
        }
    }

    public String getFileContent(String repo, String path, String ref) {
        if (!isEnabled()) {
            log.info("[github disabled] would fetch {}:{}@{}", repo, path, ref);
            return null;
        }
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> body = http.get()
                    .uri("/repos/{repo}/contents/{path}?ref={ref}", repo, path, ref)
                    .headers(this::auth)
                    .retrieve()
                    .body(Map.class);
            if (body == null || body.get("content") == null) {
                return null;
            }
            String encoded = ((String) body.get("content")).replaceAll("\\s", "");
            return new String(Base64.getDecoder().decode(encoded));
        } catch (Exception e) {
            log.warn("getFileContent failed for {}:{}@{}: {}", repo, path, ref, e.getMessage());
            return null;
        }
    }

    private void auth(HttpHeaders headers) {
        headers.setBearerAuth(token);
        headers.set("Accept", "application/vnd.github+json");
        headers.set("X-GitHub-Api-Version", "2022-11-28");
    }
}
