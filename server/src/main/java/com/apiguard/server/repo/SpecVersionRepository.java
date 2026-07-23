package com.apiguard.server.repo;

import com.apiguard.server.domain.SpecVersionEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface SpecVersionRepository extends JpaRepository<SpecVersionEntity, Long> {

    Optional<SpecVersionEntity> findFirstByApi_NameOrderByIdDesc(String name);
}
