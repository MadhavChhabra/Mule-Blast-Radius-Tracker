package com.apiguard.server.service;

import com.apiguard.server.domain.ApiEntity;
import com.apiguard.server.domain.SpecVersionEntity;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.repo.SpecVersionRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

@Service
public class SpecStore {

    private final ApiRepository apis;
    private final SpecVersionRepository specVersions;

    public SpecStore(ApiRepository apis, SpecVersionRepository specVersions) {
        this.apis = apis;
        this.specVersions = specVersions;
    }

    @Transactional
    public void store(String apiName, String source, String label, String specYaml) {
        if (apiName == null || apiName.isBlank() || specYaml == null || specYaml.isBlank()) {
            return;
        }
        ApiEntity api = apis.findByName(apiName)
                .orElseGet(() -> apis.save(new ApiEntity(apiName, source, null)));
        Optional<SpecVersionEntity> latest = specVersions.findFirstByApi_NameOrderByIdDesc(apiName);
        if (latest.isPresent() && specYaml.equals(latest.get().getRawSpec())) {
            return;
        }
        specVersions.save(new SpecVersionEntity(api, null,
                label != null && !label.isBlank() ? label : "current", specYaml));
    }

    @Transactional(readOnly = true)
    public boolean hasVersionLabel(String apiName, String label) {
        if (label == null || label.isBlank()) {
            return false;
        }
        return specVersions.findFirstByApi_NameOrderByIdDesc(apiName)
                .map(v -> label.equals(v.getVersionLabel()))
                .orElse(false);
    }
}
