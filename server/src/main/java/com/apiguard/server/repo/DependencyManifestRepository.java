package com.apiguard.server.repo;

import com.apiguard.server.domain.DependencyManifestEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface DependencyManifestRepository extends JpaRepository<DependencyManifestEntity, Long> {
    Optional<DependencyManifestEntity> findByConsumer(String consumer);
}
