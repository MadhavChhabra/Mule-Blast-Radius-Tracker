package com.apiguard.server.web;

import com.apiguard.server.domain.AuditEventEntity;
import com.apiguard.server.repo.AuditEventRepository;
import org.springframework.data.domain.PageRequest;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/audit")
public class AuditController {

    private final AuditEventRepository repo;

    public AuditController(AuditEventRepository repo) {
        this.repo = repo;
    }

    public record AuditEventDto(Long id, String ts, String actor, String action,
                                String subject, String detail) {
        static AuditEventDto from(AuditEventEntity e) {
            return new AuditEventDto(e.getId(), e.getTs().toString(), e.getActor(),
                    e.getAction(), e.getSubject(), e.getDetail());
        }
    }

    @GetMapping
    @Transactional(readOnly = true)
    public List<AuditEventDto> list(@RequestParam(defaultValue = "50") int limit) {
        int capped = Math.max(1, Math.min(500, limit));
        return repo.findAllByOrderByTsDesc(PageRequest.of(0, capped))
                .stream().map(AuditEventDto::from).toList();
    }
}
