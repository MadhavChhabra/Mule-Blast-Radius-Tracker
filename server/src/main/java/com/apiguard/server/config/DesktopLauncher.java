package com.apiguard.server.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.context.WebServerInitializedEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

import java.awt.Desktop;
import java.net.URI;

@Component
@ConditionalOnProperty(name = "apiguard.open-browser", havingValue = "true")
public class DesktopLauncher {

    private static final Logger log = LoggerFactory.getLogger(DesktopLauncher.class);

    @EventListener
    public void onReady(WebServerInitializedEvent event) {
        int port = event.getWebServer().getPort();
        String url = "http://localhost:" + port + "/";
        try {
            if (Desktop.isDesktopSupported() && Desktop.getDesktop().isSupported(Desktop.Action.BROWSE)) {
                Desktop.getDesktop().browse(URI.create(url));
                log.info("Opened Wakegraph dashboard at {}", url);
                return;
            }
        } catch (Exception e) {
            log.debug("Could not auto-open browser: {}", e.getMessage());
        }
        log.info("Wakegraph dashboard available at {}", url);
    }
}
