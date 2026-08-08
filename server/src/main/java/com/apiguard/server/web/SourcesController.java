package com.apiguard.server.web;

import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.service.AuditService;
import com.apiguard.server.service.CredentialStore;
import com.apiguard.server.service.SourcesService;
import com.apiguard.server.service.SyncJobService;
import com.apiguard.server.service.WorkspaceScoutService;

import java.util.List;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class SourcesController {

    private final SourcesService sources;
    private final AnypointCredentials creds;
    private final CredentialStore credentialStore;
    private final SyncJobService syncJob;
    private final AuditService audit;
    private final WorkspaceScoutService workspaceScout;

    public SourcesController(SourcesService sources, AnypointCredentials creds, CredentialStore credentialStore,
                             SyncJobService syncJob, AuditService audit,
                             WorkspaceScoutService workspaceScout) {
        this.sources = sources;
        this.creds = creds;
        this.credentialStore = credentialStore;
        this.syncJob = syncJob;
        this.audit = audit;
        this.workspaceScout = workspaceScout;
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

    /// Mule projects already on this machine — the zero-typing path into a first sync.
    @GetMapping("/api/sources/local-candidates")
    public List<WorkspaceScoutService.Candidate> localCandidates() {
        return workspaceScout.discover();
    }

    @PostMapping("/api/sources/anypoint")
    public SourcesService.Status configureAnypoint(@Valid @RequestBody AnypointConfigRequest req) {
        creds.update(req.clientId(), req.clientSecret(), req.orgId(), req.environment());
        credentialStore.saveAnypoint(req.clientId(), req.clientSecret(), req.orgId(), req.environment());
        audit.record("anypoint.configure", req.orgId(),
                "env=" + req.environment() + " clientId=" + req.clientId());
        return sources.status();
    }

    public record ConnectionTest(boolean ok, String orgId, String environment, int environments,
                                 String message) {
    }

    /// Answers "did my credentials work" in a second, instead of making the user start a full sync
    /// and read a failure out of the results list.
    @PostMapping("/api/sources/anypoint/test")
    public ConnectionTest testAnypoint() {
        if (!creds.isConfigured()) {
            return new ConnectionTest(false, null, null, 0,
                    "No Anypoint connection is configured yet.");
        }
        try {
            String orgId = sources.anypointOrgId();
            var envs = sources.anypointEnvironments(orgId);
            String envName = creds.environment();
            return new ConnectionTest(true, orgId, envName, envs.size(),
                    "Connected. " + envs.size() + " environment(s) visible.");
        } catch (RuntimeException e) {
            return new ConnectionTest(false, creds.orgId(), creds.environment(), 0,
                    e.getMessage() == null ? "Anypoint rejected the credentials." : e.getMessage());
        }
    }

    @PostMapping("/api/sources/anypoint/disconnect")
    public SourcesService.Status disconnectAnypoint() {
        creds.clear();
        credentialStore.clearAnypoint();
        audit.record("anypoint.disconnect", null, null);
        return sources.status();
    }

    @PostMapping("/api/sources/repos")
    public SourcesService.Status addRepo(@Valid @RequestBody RepoRequest req) {
        SourcesService.Status status = sources.addRepo(req.url());
        audit.record("sources.repo.add", SourcesService.stripUserInfo(req.url()), null);
        return status;
    }

    @PostMapping("/api/sources/repos/remove")
    public SourcesService.Status removeRepo(@Valid @RequestBody RepoRequest req) {
        SourcesService.Status status = sources.removeRepo(req.url());
        audit.record("sources.repo.remove", SourcesService.stripUserInfo(req.url()), null);
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
