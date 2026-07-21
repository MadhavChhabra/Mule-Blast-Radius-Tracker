package com.apiguard.server.web;

import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.service.AuditService;
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
    private final AuditService audit;

    public SourcesController(SourcesService sources, AnypointCredentials creds, SyncJobService syncJob,
                             AuditService audit) {
        this.sources = sources;
        this.creds = creds;
        this.syncJob = syncJob;
        this.audit = audit;
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
        audit.record("anypoint.configure", req.orgId(),
                "env=" + req.environment() + " clientId=" + req.clientId());
        return sources.status();
    }

    @PostMapping("/api/sources/anypoint/disconnect")
    public SourcesService.Status disconnectAnypoint() {
        creds.clear();
        audit.record("anypoint.disconnect", null, null);
        return sources.status();
    }

    @PostMapping("/api/sources/repos")
    public SourcesService.Status addRepo(@RequestBody RepoRequest req) {
        SourcesService.Status status = sources.addRepo(req.url());
        audit.record("sources.repo.add", req.url(), null);
        return status;
    }

    @PostMapping("/api/sources/repos/remove")
    public SourcesService.Status removeRepo(@RequestBody RepoRequest req) {
        SourcesService.Status status = sources.removeRepo(req.url());
        audit.record("sources.repo.remove", req.url(), null);
        return status;
    }

    @PostMapping("/api/sources/sync")
    public SourcesService.SyncAllResult sync() {
        audit.record("sources.sync", null, "synchronous");
        return sources.syncAll();
    }

    @PostMapping("/api/sources/sync/start")
    public SyncJobService.Progress syncStart() {
        SyncJobService.Progress p = syncJob.start();
        audit.record("sources.sync.start", null, "state=" + p.state());
        return p;
    }

    @GetMapping("/api/sources/sync/status")
    public SyncJobService.Progress syncStatus() {
        return syncJob.status();
    }

    @PostMapping("/api/sources/sync/cancel")
    public SyncJobService.Progress syncCancel() {
        SyncJobService.Progress p = syncJob.cancel();
        audit.record("sources.sync.cancel", null, "state=" + p.state());
        return p;
    }
}
