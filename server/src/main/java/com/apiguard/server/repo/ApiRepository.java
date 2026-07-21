package com.apiguard.server.repo;

import com.apiguard.server.domain.ApiEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface ApiRepository extends JpaRepository<ApiEntity, Long> {
    Optional<ApiEntity> findByName(String name);
}
