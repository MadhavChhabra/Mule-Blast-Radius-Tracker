package com.apiguard.server.web;

import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.service.SourcesService;
import com.apiguard.server.service.SyncJobService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SourcesController {

    private final SourcesService sources;
    private final AnypointCredentials creds;
    private final SyncJobService syncJob;

    public SourcesController(SourcesService sources, AnypointCredentials creds, SyncJobService syncJob) {
        this.sources = sources;
        this.creds = creds;
        this.syncJob = syncJob;
    }

    public record RepoRequest(@NotBlank String url) {
    }

    public record AnypointConfigRequest(@NotBlank String clientId, @NotBlank String clientSecret,
                                        String orgId, String environment) {
    }

    @GetMapping("/api/sources")
    public SourcesService.Status status() {
        return sources.status();
    }

    @PostMapping("/api/sources/anypoint")
    public SourcesService.Status configureAnypoint(@RequestBody AnypointConfigRequest req) {
        creds.update(req.clientId(), req.clientSecret(), req.orgId(), req.environment());
        return sources.status();
    }

    @PostMapping("/api/sources/anypoint/disconnect")
    public SourcesService.Status disconnectAnypoint() {
        creds.clear();
        return sources.status();
    }

    @PostMapping("/api/sources/repos")
    public SourcesService.Status addRepo(@RequestBody RepoRequest req) {
        return sources.addRepo(req.url());
    }

    @PostMapping("/api/sources/repos/remove")
    public SourcesService.Status removeRepo(@RequestBody RepoRequest req) {
        return sources.removeRepo(req.url());
    }

    @PostMapping("/api/sources/sync")
    public SourcesService.SyncAllResult sync() {
        return sources.syncAll();
    }

    @PostMapping("/api/sources/sync/start")
    public SyncJobService.Progress syncStart() {
        return syncJob.start();
    }

    @GetMapping("/api/sources/sync/status")
    public SyncJobService.Progress syncStatus() {
        return syncJob.status();
    }

    @PostMapping("/api/sources/sync/cancel")
    public SyncJobService.Progress syncCancel() {
        return syncJob.cancel();
    }
}
