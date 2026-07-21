package com.apiguard.server.repo;

import com.apiguard.server.domain.ChangelogEntryEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ChangelogRepository extends JpaRepository<ChangelogEntryEntity, Long> {
    List<ChangelogEntryEntity> findByApi_NameOrderByPublishedAtDesc(String apiName);

    List<ChangelogEntryEntity> findAllByOrderByPublishedAtDesc();
}
