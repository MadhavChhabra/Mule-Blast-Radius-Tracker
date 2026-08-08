package com.apiguard.server.repo;

import com.apiguard.server.domain.RepoRevisionEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RepoRevisionRepository extends JpaRepository<RepoRevisionEntity, String> {
}
