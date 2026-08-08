package com.apiguard.server.config;

import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.service.CredentialStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

@Component
public class CredentialLoader {

    private static final Logger log = LoggerFactory.getLogger(CredentialLoader.class);

    private final CredentialStore store;
    private final AnypointCredentials creds;

    public CredentialLoader(CredentialStore store, AnypointCredentials creds) {
        this.store = store;
        this.creds = creds;
    }

    @EventListener(ApplicationReadyEvent.class)
    public void restore() {
        if (creds.isConfigured()) {
            return;
        }
        try {
            store.loadAnypoint().ifPresent(c -> {
                if (notBlank(c.clientId()) && notBlank(c.clientSecret())) {
                    creds.update(c.clientId(), c.clientSecret(), c.orgId(), c.environment());
                    log.info("Restored saved Anypoint connection (org {}). Connect again in Sources to change it.",
                            c.orgId() == null ? "?" : c.orgId());
                }
            });
        } catch (RuntimeException e) {
            log.warn("Could not restore saved Anypoint credentials: {}", e.getMessage());
        }
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }
}
