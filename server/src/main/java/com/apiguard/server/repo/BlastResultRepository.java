package com.apiguard.server.repo;

import com.apiguard.server.domain.BlastResultEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface BlastResultRepository extends JpaRepository<BlastResultEntity, Long> {
}
