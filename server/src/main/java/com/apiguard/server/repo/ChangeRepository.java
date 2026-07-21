package com.apiguard.server.repo;

import com.apiguard.server.domain.ChangeRecordEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ChangeRepository extends JpaRepository<ChangeRecordEntity, Long> {
    List<ChangeRecordEntity> findByApi_NameOrderByIdDesc(String apiName);

    List<ChangeRecordEntity> findByToVersion_Id(Long toVersionId);
}
