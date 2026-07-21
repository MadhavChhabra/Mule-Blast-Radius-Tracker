package com.apiguard.server.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.ApplicationListener;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Set;

/**
 * Warns, once at startup, when the server is running without API-key auth on a
 * profile that is likely a shared deployment. A shared Wakegraph server holds
 * Anypoint credentials and repository tokens, so leaving /api/* open is a real
 * exposure. Local single-user profiles (desktop/dev/test) are exempt.
 */
@Component
public class SecurityPostureLogger implements ApplicationListener<ApplicationReadyEvent> {

    private static final Logger log = LoggerFactory.getLogger(SecurityPostureLogger.class);
    private static final Set<String> LOCAL_PROFILES = Set.of("desktop", "dev", "test");

    private final boolean authConfigured;
    private final Environment env;

    public SecurityPostureLogger(
            @Value("${apiguard.security.api-key:${APIGUARD_API_KEY_SERVER:}}") String apiKey,
            Environment env) {
        this.authConfigured = apiKey != null && !apiKey.isBlank();
        this.env = env;
    }

    @Override
    public void onApplicationEvent(ApplicationReadyEvent event) {
        boolean local = Arrays.stream(env.getActiveProfiles()).anyMatch(LOCAL_PROFILES::contains);
        if (!authConfigured && !local) {
            log.warn("""

                    ****************************************************************
                    * Wakegraph is running WITHOUT API-key authentication.        *
                    * All /api/* endpoints are open — anyone who can reach this    *
                    * server can read your estate and trigger syncs, and it holds  *
                    * Anypoint credentials and repo tokens.                        *
                    * Set apiguard.security.api-key (or APIGUARD_API_KEY_SERVER)   *
                    * before exposing this server beyond localhost.                *
                    ****************************************************************""");
        }
    }
}
