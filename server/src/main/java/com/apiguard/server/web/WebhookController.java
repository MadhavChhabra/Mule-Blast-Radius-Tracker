package com.apiguard.server.web;

import com.apiguard.server.notify.GitHubClient;
import com.apiguard.server.service.AnalysisService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

@RestController
public class WebhookController {

    private static final Logger log = LoggerFactory.getLogger(WebhookController.class);
    private final ObjectMapper mapper = new ObjectMapper();

    private final AnalysisService analysisService;
    private final GitHubClient github;
    private final String secret;
    private final String specPath;
    private final String apiName;

    public WebhookController(AnalysisService analysisService, GitHubClient github,
                             @Value("${apiguard.github.webhook-secret:}") String secret,
                             @Value("${apiguard.webhook.spec-path:}") String specPath,
                             @Value("${apiguard.webhook.api-name:}") String apiName) {
        this.analysisService = analysisService;
        this.github = github;
        this.secret = secret;
        this.specPath = specPath;
        this.apiName = apiName;
    }

    @PostMapping("/webhooks/github")
    public ResponseEntity<String> onEvent(
            @RequestHeader(value = "X-GitHub-Event", required = false) String event,
            @RequestHeader(value = "X-Hub-Signature-256", required = false) String signature,
            @RequestBody String body) {

        if (!verifySignature(body, signature)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body("invalid signature");
        }
        if (!"pull_request".equals(event)) {
            return ResponseEntity.ok("ignored: " + event);
        }

        try {
            JsonNode payload = mapper.readTree(body);
            String action = payload.path("action").asText();
            if (!action.equals("opened") && !action.equals("synchronize") && !action.equals("reopened")) {
                return ResponseEntity.ok("ignored action: " + action);
            }
            int prNumber = payload.path("number").asInt();
            String repo = payload.path("repository").path("full_name").asText(null);
            String baseSha = payload.path("pull_request").path("base").path("sha").asText(null);
            String headSha = payload.path("pull_request").path("head").path("sha").asText(null);

            if (specPath == null || specPath.isBlank() || repo == null) {
                log.info("Webhook received for {}#{} but no spec-path configured — skipping analysis.", repo, prNumber);
                return ResponseEntity.accepted().body("received; analysis skipped (configure apiguard.webhook.spec-path)");
            }

            String oldSpec = github.getFileContent(repo, specPath, baseSha);
            String newSpec = github.getFileContent(repo, specPath, headSha);
            if (oldSpec == null || newSpec == null) {
                return ResponseEntity.accepted().body("received; could not fetch spec at base/head");
            }

            var response = analysisService.analyze(new AnalysisService.AnalyzeCommand(
                    apiName == null || apiName.isBlank() ? repo : apiName, repo,
                    oldSpec, newSpec, baseSha, headSha, "#" + prNumber, true));
            return ResponseEntity.ok("analyzed: " + response.summary().breaking() + " breaking change(s)");
        } catch (Exception e) {
            log.error("Webhook processing failed", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("error: " + e.getMessage());
        }
    }

    private boolean verifySignature(String body, String signature) {
        if (secret == null || secret.isBlank()) {
            return true;
        }
        if (signature == null || !signature.startsWith("sha256=")) {
            return false;
        }
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            String expected = "sha256=" + HexFormat.of().formatHex(mac.doFinal(body.getBytes(StandardCharsets.UTF_8)));
            return constantTimeEquals(expected, signature);
        } catch (Exception e) {
            return false;
        }
    }

    private static boolean constantTimeEquals(String a, String b) {
        if (a.length() != b.length()) {
            return false;
        }
        int r = 0;
        for (int i = 0; i < a.length(); i++) {
            r |= a.charAt(i) ^ b.charAt(i);
        }
        return r == 0;
    }
}
