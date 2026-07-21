package com.apiguard.server.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

@Component
public class ApiKeyFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ApiKeyFilter.class);

    private final String apiKey;

    public ApiKeyFilter(@Value("${apiguard.security.api-key:${APIGUARD_API_KEY_SERVER:}}") String apiKey) {
        this.apiKey = apiKey == null ? "" : apiKey.trim();
        if (!this.apiKey.isEmpty()) {
            log.info("API-key auth is ON for /api/* (X-API-Key or Bearer).");
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return apiKey.isEmpty()
                || !request.getRequestURI().startsWith("/api/")
                || "/api/health".equals(request.getRequestURI())
                || "OPTIONS".equalsIgnoreCase(request.getMethod());
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String given = request.getHeader("X-API-Key");
        if (given == null) {
            String auth = request.getHeader("Authorization");
            if (auth != null && auth.startsWith("Bearer ")) {
                given = auth.substring("Bearer ".length());
            }
        }
        if (given != null && MessageDigest.isEqual(
                given.trim().getBytes(StandardCharsets.UTF_8), apiKey.getBytes(StandardCharsets.UTF_8))) {
            chain.doFilter(request, response);
            return;
        }
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        response.getWriter().write("{\"error\":\"API key required — send X-API-Key or Authorization: Bearer.\"}");
    }
}
