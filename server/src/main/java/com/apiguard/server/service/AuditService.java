package com.apiguard.server.service;

import com.apiguard.server.domain.AuditEventEntity;
import com.apiguard.server.repo.AuditEventRepository;
import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.context.request.RequestAttributes;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

@Service
public class AuditService {

    private static final Logger log = LoggerFactory.getLogger(AuditService.class);

    private final AuditEventRepository repo;

    public AuditService(AuditEventRepository repo) {
        this.repo = repo;
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void record(String action, String subject, String detail) {
        try {
            repo.save(new AuditEventEntity(currentActor(), action, subject, truncate(detail, 2048)));
        } catch (RuntimeException e) {
            log.warn("audit write failed action={} subject={}: {}", action, subject, e.getMessage());
        }
    }

    private static String truncate(String s, int max) {
        if (s == null) return null;
        return s.length() <= max ? s : s.substring(0, max);
    }

    private static String currentActor() {
        RequestAttributes attrs = RequestContextHolder.getRequestAttributes();
        if (attrs instanceof ServletRequestAttributes s) {
            HttpServletRequest req = s.getRequest();
            String key = req.getHeader("X-API-Key");
            if (key == null || key.isBlank()) {
                String bearer = req.getHeader("Authorization");
                if (bearer != null && bearer.startsWith("Bearer ")) {
                    key = bearer.substring(7);
                }
            }
            if (key != null && !key.isBlank()) {
                return "api-key:" + fingerprint(key);
            }
            return "anon@" + req.getRemoteAddr();
        }
        return "system";
    }

    private static String fingerprint(String key) {
        int len = key.length();
        if (len <= 4) return "****";
        return key.substring(0, 2) + "…" + key.substring(len - 2);
    }
}
