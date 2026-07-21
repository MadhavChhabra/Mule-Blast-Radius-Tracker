package com.apiguard.server.web;

import com.apiguard.core.blast.ManifestLoader;
import com.apiguard.server.domain.DependencyEdgeEntity;
import com.apiguard.server.domain.DependencyManifestEntity;
import com.apiguard.server.service.ManifestService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/manifests")
public class ManifestController {

    private final ManifestService manifestService;

    public ManifestController(ManifestService manifestService) {
        this.manifestService = manifestService;
    }

    @PostMapping(value = "/dependency", consumes = {"text/plain", "application/x-yaml", "application/yaml"})
    public Dtos.ManifestDto ingestDependency(@RequestBody String yaml) {
        DependencyManifestEntity e = manifestService.ingestDependency(ManifestLoader.loadDependency(yaml));
        return toDto(e);
    }

    @PostMapping(value = "/source", consumes = {"text/plain", "application/x-yaml", "application/yaml"})
    public String ingestSource(@RequestBody String yaml) {
        manifestService.ingestSources(ManifestLoader.loadSources(yaml));
        return "ok";
    }

    @GetMapping
    public List<Dtos.ManifestDto> list() {
        return manifestService.all().stream().map(ManifestController::toDto).toList();
    }

    private static Dtos.ManifestDto toDto(DependencyManifestEntity e) {
        List<Dtos.EdgeDto> edges = e.getEdges().stream()
                .map((DependencyEdgeEntity ed) -> new Dtos.EdgeDto(ed.getApiName(), ed.getEndpoint(), ed.getField()))
                .toList();
        return new Dtos.ManifestDto(e.getConsumer(), e.getOwnerTeam(), List.copyOf(e.getReviewers()),
                e.getSlackChannel(), e.getSourceRepo(), edges);
    }
}
