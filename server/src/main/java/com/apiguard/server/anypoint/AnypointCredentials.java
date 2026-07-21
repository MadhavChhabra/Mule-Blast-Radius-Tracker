package com.apiguard.server.anypoint;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
public class AnypointCredentials {

    private volatile String clientId;
    private volatile String clientSecret;
    private volatile String orgId;
    private volatile String environment;
    private volatile Runnable onChange = () -> {};

    public AnypointCredentials(
            @Value("${apiguard.anypoint.client-id:}") String clientId,
            @Value("${apiguard.anypoint.client-secret:}") String clientSecret,
            @Value("${apiguard.anypoint.org-id:}") String orgId,
            @Value("${apiguard.anypoint.environment:}") String environment) {
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.orgId = orgId;
        this.environment = environment;
    }

    public synchronized void update(String clientId, String clientSecret, String orgId, String environment) {
        this.clientId = clientId;
        this.clientSecret = clientSecret;

        if (notBlank(orgId)) {
            this.orgId = orgId;
        }
        if (notBlank(environment)) {
            this.environment = environment;
        }
        onChange.run();
    }

    public void clear() {
        this.clientId = null;
        this.clientSecret = null;
        onChange.run();
    }

    public void setOnChange(Runnable onChange) {
        this.onChange = onChange;
    }

    public boolean isConfigured() {
        return notBlank(clientId) && notBlank(clientSecret);
    }

    public String clientId() {
        return clientId;
    }

    public String clientSecret() {
        return clientSecret;
    }

    public String orgId() {
        return orgId;
    }

    public String environment() {
        return environment;
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }
}
