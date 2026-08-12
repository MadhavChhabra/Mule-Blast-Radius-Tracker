package com.apiguard.server.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

/// A plain fixed-window limiter per client address. A sync or an org scan is expensive, and one
/// looping script should not be able to monopolise the server. Off when the limit is <= 0.
@Component
@Order(1)
public class RateLimitFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(RateLimitFilter.class);

    private record Window(long startedAtSecond, AtomicInteger count) {
    }

    private final int limitPerMinute;
    private final Map<String, Window> windows = new ConcurrentHashMap<>();

    public RateLimitFilter(@Value("${apiguard.security.rate-limit-per-minute:600}") int limitPerMinute) {
        this.limitPerMinute = limitPerMinute;
        if (limitPerMinute > 0) {
            log.info("Rate limit: {} requests/minute per client for /api/*.", limitPerMinute);
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return limitPerMinute <= 0
                || !request.getRequestURI().startsWith("/api/")
                || "/api/health".equals(request.getRequestURI());
    }

    private String clientKey(HttpServletRequest request) {
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            int comma = forwarded.indexOf(',');
            return (comma < 0 ? forwarded : forwarded.substring(0, comma)).trim();
        }
        String addr = request.getRemoteAddr();
        return addr == null ? "unknown" : addr;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        long minute = System.currentTimeMillis() / 60_000L;
        Window window = windows.compute(clientKey(request), (key, existing) ->
                existing == null || existing.startedAtSecond() != minute
                        ? new Window(minute, new AtomicInteger(0))
                        : existing);

        int used = window.count().incrementAndGet();
        if (used > limitPerMinute) {
            response.setStatus(429);
            // Without the charset the writer falls back to ISO-8859-1 and the dash reaches the user
            // as a literal "?".
            response.setContentType("application/json;charset=UTF-8");
            response.setHeader("Retry-After", "60");
            response.getWriter().write(
                    "{\"error\":\"Too many requests — try again in a minute.\"}");
            return;
        }
        if (windows.size() > 10_000) {
            windows.entrySet().removeIf(e -> e.getValue().startedAtSecond() != minute);
        }
        chain.doFilter(request, response);
    }
}
