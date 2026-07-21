package com.apiguard.server.service;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.spec.SpecLoader;
import com.apiguard.core.spec.SpecSurface;
import com.apiguard.server.web.Dtos;
import io.swagger.v3.oas.models.OpenAPI;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class PropagationService {

    private final ManifestService manifestService;

    public PropagationService(ManifestService manifestService) {
        this.manifestService = manifestService;
    }

    @Transactional(readOnly = true)
    public Dtos.PropagationResponse propagate(String api, String spec) {
        OpenAPI parsed = SpecLoader.loadString(spec);
        Map<String, LinkedHashSet<String>> surface = SpecSurface.responseFields(parsed);
        BlastRadiusResolver resolver = manifestService.buildResolver();

        List<Dtos.PropagationField> items = new ArrayList<>();
        int fieldCount = 0;
        int impactedFields = 0;
        Set<String> impactedConsumers = new LinkedHashSet<>();

        for (Map.Entry<String, LinkedHashSet<String>> ep : surface.entrySet()) {
            String endpoint = ep.getKey();
            for (String field : ep.getValue()) {
                fieldCount++;
                List<Dtos.ConsumerDto> downstream = resolver.downstreamOf(api, endpoint, field).stream()
                        .map(Dtos.ConsumerDto::from).toList();
                List<Dtos.UpstreamDto> upstream = resolver.upstreamOf(api, endpoint, field).stream()
                        .map(Dtos.UpstreamDto::from).toList();
                if (!downstream.isEmpty()) {
                    impactedFields++;
                    downstream.forEach(c -> impactedConsumers.add(c.consumer()));
                }
                items.add(new Dtos.PropagationField(endpoint, field, downstream.size(), downstream, upstream));
            }
        }

        items.sort(Comparator.comparingInt(Dtos.PropagationField::consumerCount).reversed()
                .thenComparing(Dtos.PropagationField::endpoint)
                .thenComparing(Dtos.PropagationField::field));

        String title = parsed.getInfo() != null ? parsed.getInfo().getTitle() : null;
        String version = parsed.getInfo() != null ? parsed.getInfo().getVersion() : null;
        return new Dtos.PropagationResponse(api, title, version, surface.size(), fieldCount,
                impactedFields, impactedConsumers.size(), items);
    }
}
