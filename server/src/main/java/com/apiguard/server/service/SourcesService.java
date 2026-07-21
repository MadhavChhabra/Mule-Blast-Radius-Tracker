package com.apiguard.server.service;

import com.apiguard.core.mule.MuleScan;
import com.apiguard.server.anypoint.AnypointClient;
import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.anypoint.AnypointSyncService;
import com.apiguard.server.domain.ScanSourceEntity;
import com.apiguard.server.repo.ScanSourceRepository;
import com.apiguard.server.web.Dtos;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import org.springframework.beans.factory.annotation.Value;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

@Service
public class SourcesService {

    private static final Logger log = LoggerFactory.getLogger(SourcesService.class);

    private final ScanSourceRepository repos;
    private final ScanService scanService;
    private final AnypointClient anypointClient;
    private final AnypointSyncService anypointSync;
    private final AnypointCredentials creds;
    private final ScmOrgService scmOrg;
    private final int scanParallelism;

    public SourcesService(ScanSourceRepository repos, ScanService scanService, AnypointClient anypointClient,
                          AnypointSyncService anypointSync, AnypointCredentials creds, ScmOrgService scmOrg,
                          @Value("${apiguard.scan.parallelism:6}") int scanParallelism) {
        this.repos = repos;
        this.scanService = scanService;
        this.anypointClient = anypointClient;
        this.anypointSync = anypointSync;
        this.creds = creds;
        this.scmOrg = scmOrg;
        this.scanParallelism = scanParallelism;
    }

    public record RepoResult(String url, int apps, List<String> appNames, String error) {
    }

    public interface SyncListener {
        default void phase(String label) {
        }

        default void planned(int totalRepos) {
        }

        default void repoFinished(RepoResult result) {
        }

        default boolean isCancelled() {
            return false;
        }
    }

    private static final SyncListener NO_LISTENER = new SyncListener() {
    };

    public record SyncAllResult(boolean anypointRan, AnypointSyncService.SyncResult anypoint,
                                List<RepoResult> repos, int totalApps, String note) {
    }

    public record Status(boolean anypointConfigured, String anypointOrg, String anypointEnv,
                         String anypointBaseUrl, List<String> repos) {
    }

    public Status status() {
        return new Status(creds.isConfigured(), creds.orgId(), creds.environment(),
                anypointClient.baseUrl(), repoUrls());
    }

    public Status addRepo(String url) {
        String clean = url == null ? "" : url.trim();
        if (clean.isEmpty()) {
            throw new IllegalArgumentException("Repo URL / path is required.");
        }
        if (!repos.existsByUrl(clean)) {
            repos.save(new ScanSourceEntity(clean));
        }
        return status();
    }

    public Status removeRepo(String url) {
        repos.findByUrl(url == null ? "" : url.trim()).ifPresent(repos::delete);
        return status();
    }

    public SyncAllResult syncAll() {
        return syncAll(NO_LISTENER);
    }

    public SyncAllResult syncAll(SyncListener listener) {

        AnypointSyncService.SyncResult anypoint = null;
        boolean anypointRan = false;
        if (anypointClient.isEnabled()) {
            anypointRan = true;
            listener.phase("Syncing Anypoint catalog + contracts…");
            try {
                anypoint = anypointSync.sync();
            } catch (RuntimeException e) {
                log.warn("Anypoint sync failed during Sync-everything: {}", e.getMessage());
            }
        }

        listener.phase("Listing repos…");
        List<RepoResult> repoResults = new ArrayList<>();
        List<ScanTask> tasks = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        int duplicates = 0;
        for (String url : repoUrls()) {
            if (listener.isCancelled()) {
                break;
            }
            var org = scmOrg.parse(url);
            if (org.isEmpty()) {
                duplicates += addTask(tasks, seen, url, url) ? 0 : 1;
                continue;
            }
            List<ScmOrgService.RepoRef> orgRepos;
            try {
                orgRepos = scmOrg.listRepos(org.get());
            } catch (RuntimeException e) {
                RepoResult failed = new RepoResult(url, 0, List.of(),
                        e.getMessage() == null ? "could not list the org's repos" : e.getMessage());
                repoResults.add(failed);
                listener.repoFinished(failed);
                continue;
            }
            if (orgRepos.isEmpty()) {
                RepoResult empty = new RepoResult(url, 0, List.of(), "org/workspace has no repos");
                repoResults.add(empty);
                listener.repoFinished(empty);
                continue;
            }
            log.info("Org {} expanded to {} repo(s)", org.get().owner(), orgRepos.size());
            for (ScmOrgService.RepoRef repo : orgRepos) {
                duplicates += addTask(tasks, seen, repo.webUrl(), repo.cloneUrl()) ? 0 : 1;
            }
        }

        listener.planned(tasks.size());
        listener.phase(tasks.isEmpty() ? "No repos to scan" : "Scanning " + tasks.size() + " repo(s)…");
        Map<String, List<String>> undeclaredByApp = new LinkedHashMap<>();
        Map<String, List<String>> driftByApp = new LinkedHashMap<>();
        int totalApps = runScans(tasks, repoResults, listener, undeclaredByApp, driftByApp);

        String note = buildNote(anypointRan, anypoint, repoResults, totalApps, duplicates,
                undeclaredByApp, driftByApp);
        log.info("Sync everything: anypointRan={} repos={} totalMuleApps={} duplicatesSkipped={} "
                        + "undeclaredApps={} configDriftApps={}",
                anypointRan, repoResults.size(), totalApps, duplicates,
                undeclaredByApp.size(), driftByApp.size());
        return new SyncAllResult(anypointRan, anypoint, repoResults, totalApps, note);
    }

    private record ScanTask(String displayUrl, String scanUrl) {
    }

    private static boolean addTask(List<ScanTask> tasks, Set<String> seen, String displayUrl, String scanUrl) {
        if (!seen.add(normalizeRepoUrl(scanUrl))) {
            return false;
        }
        tasks.add(new ScanTask(displayUrl, scanUrl));
        return true;
    }

    public static String normalizeRepoUrl(String url) {
        String s = url == null ? "" : url.trim().toLowerCase(java.util.Locale.ROOT);
        s = s.replaceFirst("^https?://", "").replaceFirst("^[^@/]+@", "");
        while (s.endsWith("/")) {
            s = s.substring(0, s.length() - 1);
        }
        return s.endsWith(".git") ? s.substring(0, s.length() - 4) : s;
    }

    private int runScans(List<ScanTask> tasks, List<RepoResult> repoResults, SyncListener listener,
                         Map<String, List<String>> undeclaredByApp,
                         Map<String, List<String>> driftByApp) {
        if (tasks.isEmpty()) {
            return 0;
        }
        int threads = Math.max(1, Math.min(scanParallelism, tasks.size()));
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        int totalApps = 0;
        try {
            List<Future<List<MuleScan>>> futures = tasks.stream()
                    .map(t -> pool.submit(() -> scanService.fetchAndScan(t.scanUrl())))
                    .toList();
            for (int i = 0; i < tasks.size(); i++) {
                ScanTask task = tasks.get(i);
                if (listener.isCancelled()) {
                    futures.get(i).cancel(true);
                    RepoResult skipped = new RepoResult(task.displayUrl(), 0, List.of(), "cancelled");
                    repoResults.add(skipped);
                    listener.repoFinished(skipped);
                    continue;
                }
                RepoResult row;
                try {
                    Dtos.ScanResultDto r = scanService.ingest(futures.get(i).get());
                    List<String> names = r.scans().stream().map(Dtos.MuleScanDto::app).toList();
                    for (Dtos.MuleScanDto scan : r.scans()) {
                        if (scan.undeclaredApis() != null && !scan.undeclaredApis().isEmpty()) {
                            undeclaredByApp.put(scan.app(), scan.undeclaredApis());
                        }
                        if (scan.configDrift() != null && !scan.configDrift().isEmpty()) {
                            driftByApp.put(scan.app(), scan.configDrift().stream()
                                    .map(d -> d.configName() + "→" + d.unresolvedPlaceholder())
                                    .toList());
                        }
                    }
                    row = new RepoResult(task.displayUrl(), r.apps(), names, null);
                    totalApps += r.apps();
                } catch (ExecutionException e) {
                    String msg = e.getCause() == null || e.getCause().getMessage() == null
                            ? "scan failed" : e.getCause().getMessage();
                    row = new RepoResult(task.displayUrl(), 0, List.of(), msg);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                    row = new RepoResult(task.displayUrl(), 0, List.of(), "scan interrupted");
                } catch (RuntimeException e) {
                    row = new RepoResult(task.displayUrl(), 0, List.of(),
                            e.getMessage() == null ? "ingest failed" : e.getMessage());
                }
                repoResults.add(row);
                listener.repoFinished(row);
            }
        } finally {
            pool.shutdownNow();
        }
        return totalApps;
    }

    private static String buildNote(boolean anypointRan, AnypointSyncService.SyncResult anypoint,
                                    List<RepoResult> repos, int totalApps, int duplicates,
                                    Map<String, List<String>> undeclaredByApp,
                                    Map<String, List<String>> driftByApp) {
        List<String> failed = repos.stream().filter(r -> r.error() != null).map(RepoResult::url).toList();
        StringBuilder sb = new StringBuilder();
        if (anypointRan && anypoint == null) {
            sb.append("Anypoint sync failed (check scopes / rate limit). ");
        }
        if (!failed.isEmpty()) {
            sb.append(failed.size()).append(" repo(s) could not be scanned. ");
        }
        if (duplicates > 0) {
            sb.append(duplicates).append(" duplicate repo(s) skipped (already covered by an org URL). ");
        }
        if (totalApps == 0 && !repos.isEmpty()) {
            sb.append("No Mule projects found in the repos (need pom.xml + src/main/mule). ");
        }
        if (anypoint != null && anypoint.rateLimited()) {
            sb.append("Anypoint rate-limited — re-run if anything looks missing. ");
        }
        if (!undeclaredByApp.isEmpty()) {
            sb.append(undeclaredByApp.size())
                    .append(" app(s) call APIs not declared in pom.xml (Exchange coverage gap): ");
            appendCoverage(sb, undeclaredByApp);
            sb.append(". ");
        }
        if (!driftByApp.isEmpty()) {
            sb.append(driftByApp.size())
                    .append(" app(s) have unresolved property placeholders in <request-config> host: ");
            appendCoverage(sb, driftByApp);
            sb.append(". ");
        }
        return sb.length() == 0 ? null : sb.toString().trim();
    }

    private static void appendCoverage(StringBuilder sb, Map<String, List<String>> byApp) {
        int shown = 0;
        for (Map.Entry<String, List<String>> e : byApp.entrySet()) {
            if (shown++ > 0) sb.append("; ");
            if (shown > 3) {
                sb.append("+").append(byApp.size() - 3).append(" more");
                break;
            }
            sb.append(e.getKey()).append(" → ").append(String.join(", ", e.getValue()));
        }
    }

    private List<String> repoUrls() {
        return repos.findAll().stream().map(ScanSourceEntity::getUrl).toList();
    }
}
