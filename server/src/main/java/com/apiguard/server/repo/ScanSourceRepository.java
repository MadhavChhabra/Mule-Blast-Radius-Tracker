package com.apiguard.server.repo;

import com.apiguard.server.domain.ScanSourceEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ScanSourceRepository extends JpaRepository<ScanSourceEntity, Long> {
    Optional<ScanSourceEntity> findByUrl(String url);

    boolean existsByUrl(String url);
}
