package com.apiguard.server.web;

import com.apiguard.server.domain.ApiEntity;
import com.apiguard.server.domain.ChangeRecordEntity;
import com.apiguard.server.domain.ChangelogEntryEntity;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.repo.ChangeRepository;
import com.apiguard.server.repo.ChangelogRepository;
import com.apiguard.server.service.GraphService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class ReadControllers {

    private final ApiRepository apis;
    private final ChangeRepository changes;
    private final ChangelogRepository changelogs;
    private final GraphService graphService;

    public ReadControllers(ApiRepository apis, ChangeRepository changes,
                           ChangelogRepository changelogs, GraphService graphService) {
        this.apis = apis;
        this.changes = changes;
        this.changelogs = changelogs;
        this.graphService = graphService;
    }

    public record ApiDto(Long id, String name, String repo, String createdAt) {
    }

    @GetMapping("/api/apis")
    public List<ApiDto> listApis() {
        return apis.findAll().stream()
                .map(a -> new ApiDto(a.getId(), a.getName(), a.getRepo(), a.getCreatedAt().toString()))
                .toList();
    }

    @GetMapping("/api/apis/{name}/changes")
    public List<Dtos.ChangeDto> changesFor(@PathVariable String name) {
        return changes.findByApi_NameOrderByIdDesc(name).stream()
                .map(ChangeRecordEntity::toChange)
                .map(Dtos.ChangeDto::from)
                .toList();
    }

    @GetMapping("/api/changelog")
    public List<Dtos.ChangelogDto> changelog(@RequestParam(required = false) String api) {
        List<ChangelogEntryEntity> entries = (api == null || api.isBlank())
                ? changelogs.findAllByOrderByPublishedAtDesc()
                : changelogs.findByApi_NameOrderByPublishedAtDesc(api);
        return entries.stream()
                .map(e -> new Dtos.ChangelogDto(e.getId(),
                        e.getApi() != null ? e.getApi().getName() : null,
                        e.getVersionLabel(), e.getMarkdown(), e.getPublishedAt().toString()))
                .toList();
    }

    @GetMapping("/api/graph")
    public Dtos.GraphDto graph() {
        return graphService.build();
    }
}
