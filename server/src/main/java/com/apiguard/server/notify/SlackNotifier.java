package com.apiguard.server.notify;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Map;

@Component
public class SlackNotifier {

    private static final Logger log = LoggerFactory.getLogger(SlackNotifier.class);

    private final String webhookUrl;
    private final RestClient http = RestClient.create();

    public SlackNotifier(@Value("${apiguard.slack.webhook-url:}") String webhookUrl) {
        this.webhookUrl = webhookUrl;
    }

    public boolean isEnabled() {
        return webhookUrl != null && !webhookUrl.isBlank();
    }

    public void post(String markdownText) {
        if (!isEnabled()) {
            log.info("[slack disabled] would post:\n{}", markdownText);
            return;
        }
        try {
            http.post().uri(webhookUrl)
                    .body(Map.of("text", markdownText))
                    .retrieve()
                    .toBodilessEntity();
        } catch (Exception e) {
            log.warn("Slack notification failed: {}", e.getMessage());
        }
    }
}
