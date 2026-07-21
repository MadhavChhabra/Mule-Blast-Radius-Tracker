package com.apiguard.server.repo;

import com.apiguard.server.domain.AuditEventEntity;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AuditEventRepository extends JpaRepository<AuditEventEntity, Long> {
    List<AuditEventEntity> findAllByOrderByTsDesc(Pageable pageable);
}
