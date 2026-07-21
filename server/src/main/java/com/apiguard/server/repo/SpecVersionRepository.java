package com.apiguard.server.repo;

import com.apiguard.server.domain.SpecVersionEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SpecVersionRepository extends JpaRepository<SpecVersionEntity, Long> {
}
