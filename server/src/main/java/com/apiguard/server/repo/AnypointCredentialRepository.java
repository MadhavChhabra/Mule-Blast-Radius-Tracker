package com.apiguard.server.repo;

import com.apiguard.server.domain.AnypointCredentialEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface AnypointCredentialRepository extends JpaRepository<AnypointCredentialEntity, Integer> {
}
