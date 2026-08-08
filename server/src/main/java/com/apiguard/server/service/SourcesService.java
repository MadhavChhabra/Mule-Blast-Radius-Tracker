package com.apiguard.server.service;

import com.apiguard.core.mule.MuleScan;
import com.apiguard.server.anypoint.AnypointClient;
import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.anypoint.AnypointSyncService;
import com.apiguard.server.domain.RepoRevisionEntity;
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
    private final RepoFetchService repoFetch;
    private final com.apiguard.server.config.CredentialCipher cipher;
    private final com.apiguard.server.repo.RepoRevisionRepository revisions;
    private final int scanParallelism;
    private final boolean incrementalScan;

    public SourcesService(ScanSourceRepository repos, ScanService scanService, AnypointClient anypointClient,
                          AnypointSyncService anypointSync, AnypointCredentials creds, ScmOrgService scmOrg,
                          RepoFetchService repoFetch, com.apiguard.server.config.CredentialCipher cipher,
                          com.apiguard.server.repo.RepoRevisionRepository revisions,
                          @Value("${apiguard.scan.parallelism:6}") int scanParallelism,
                          @Value("${apiguard.scan.incremental:true}") boolean incrementalScan) {
        this.revisions = revisions;
        this.incrementalScan = incrementalScan;
        this.repos = repos;
        this.scanService = scanService;
        this.anypointClient = anypointClient;
        this.anypointSync = anypointSync;
        this.creds = creds;
        this.scmOrg = scmOrg;
        this.repoFetch = repoFetch;
        this.cipher = cipher;
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

    public record RepoSource(String url, String lastSyncedAt, Integer lastApps, String lastError) {
    }

    public record Status(boolean anypointConfigured, String anypointOrg, String anypointEnv,
                         String anypointBaseUrl, List<String> repos, List<RepoSource> repoDetails) {
    }

    public String anypointOrgId() {
        String configured = creds.orgId();
        return configured == null || configured.isBlank() ? anypointClient.defaultOrgId() : configured;
    }

    public List<java.util.Map<String, Object>> anypointEnvironments(String orgId) {
        return anypointClient.environments(orgId);
    }

    public Status status() {
        List<RepoSource> details = repos.findAll().stream()
                .map(s -> new RepoSource(s.getUrl(),
                        s.getLastSyncedAt() == null ? null : s.getLastSyncedAt().toString(),
                        s.getLastApps(), s.getLastError()))
                .toList();
        return new Status(creds.isConfigured(), creds.orgId(), creds.environment(),
                anypointClient.baseUrl(), details.stream().map(RepoSource::url).toList(), details);
    }

    public Status addRepo(String url) {
        String given = url == null ? "" : url.trim();
        if (given.isEmpty()) {
            throw new IllegalArgumentException("Repo URL / path is required.");
        }
        repoFetch.validateSource(given);
        String clean = stripUserInfo(given);
        String userInfo = userInfoOf(given);
        if (userInfo != null && !cipher.isConfigured()) {
            throw new IllegalArgumentException(
                    "This repo URL carries a token, but no encryption key is available to store it safely. "
                            + "Set APIGUARD_ENCRYPTION_KEY, or register the repo without the token.");
        }
        ScanSourceEntity existing = repos.findByUrl(clean).orElse(null);
        if (existing == null) {
            repos.save(new ScanSourceEntity(clean, userInfo == null ? null : cipher.encrypt(userInfo)));
        } else if (userInfo != null) {
            existing.setCredential(cipher.encrypt(userInfo));
            repos.save(existing);
        }
        return status();
    }

    public Status removeRepo(String url) {
        repos.findByUrl(stripUserInfo(url == null ? "" : url.trim())).ifPresent(repos::delete);
        return status();
    }

    // A token pasted into the URL is the documented way to reach a private repo, so it must be
    // accepted — but it is a credential, and it never belongs in the URL we store, return or log.
    public static String stripUserInfo(String url) {
        return url == null ? "" : url.replaceFirst("^(https?://)[^@/]+@", "$1");
    }

    static String userInfoOf(String url) {
        if (url == null) {
            return null;
        }
        var m = java.util.regex.Pattern.compile("^https?://([^@/]+)@").matcher(url);
        return m.find() ? m.group(1) : null;
    }

    private static String withUserInfo(String url, String userInfo) {
        return userInfo == null || userInfo.isBlank()
                ? url
                : url.replaceFirst("^(https?://)", "$1" + java.util.regex.Matcher.quoteReplacement(userInfo) + "@");
    }

    /// The URL actually handed to git / the SCM API, with any stored credential re-attached.
    private String scanUrlOf(ScanSourceEntity source) {
        String credential = source.getCredential();
        if (credential == null || credential.isBlank()) {
            return source.getUrl();
        }
        try {
            return withUserInfo(source.getUrl(), cipher.decrypt(credential));
        } catch (RuntimeException e) {
            log.warn("Stored credential for {} could not be decrypted (encryption key changed?) — "
                    + "re-add the repo with its token.", source.getUrl());
            return source.getUrl();
        }
    }

    /// Splits credentials out of rows written before the credential column existed, so no plaintext
    /// token survives a restart. Idempotent — rows already clean are untouched.
    @org.springframework.context.event.EventListener(
            org.springframework.boot.context.event.ApplicationReadyEvent.class)
    @org.springframework.transaction.annotation.Transactional
    public void migrateStoredCredentials() {
        int moved = 0;
        for (ScanSourceEntity source : repos.findAll()) {
            String userInfo = userInfoOf(source.getUrl());
            if (userInfo == null) {
                continue;
            }
            source.setUrl(stripUserInfo(source.getUrl()));
            source.setCredential(cipher.isConfigured() ? cipher.encrypt(userInfo) : null);
            repos.save(source);
            moved++;
        }
        if (moved > 0) {
            log.info("Moved {} repo credential(s) out of the stored URL{}.", moved,
                    cipher.isConfigured() ? " and encrypted them" : " (no encryption key — re-add the token)");
        }
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
        for (ScanSourceEntity source : repos.findAll()) {
            if (listener.isCancelled()) {
                break;
            }
            // Displayed rows stay credential-free; only the scan URL carries the token.
            String url = source.getUrl();
            String scanUrl = scanUrlOf(source);
            var org = scmOrg.parse(scanUrl);
            if (org.isEmpty()) {
                duplicates += addTask(tasks, seen, url, scanUrl) ? 0 : 1;
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
        List<String> unchangedRepos = new ArrayList<>();
        int totalApps = runScans(tasks, repoResults, listener, undeclaredByApp, driftByApp, unchangedRepos);

        recordPerSourceOutcome(repoResults.stream()
                .filter(r -> !unchangedRepos.contains(r.url()))
                .toList());
        String note = buildNote(anypointRan, anypoint, repoResults, totalApps, duplicates,
                undeclaredByApp, driftByApp, unchangedRepos.size());
        log.info("Sync everything: anypointRan={} repos={} totalMuleApps={} duplicatesSkipped={} "
                        + "undeclaredApps={} configDriftApps={}",
                anypointRan, repoResults.size(), totalApps, duplicates,
                undeclaredByApp.size(), driftByApp.size());
        return new SyncAllResult(anypointRan, anypoint, repoResults, totalApps, note);
    }

    /// Folds each run's results back onto the registered source so the Sources list can say what a
    /// repo last contributed. An org URL aggregates every repo it expanded to.
    private void recordPerSourceOutcome(List<RepoResult> results) {
        if (results.isEmpty()) {
            return;
        }
        java.time.Instant now = java.time.Instant.now();
        for (ScanSourceEntity source : repos.findAll()) {
            String key = normalizeRepoUrl(source.getUrl());
            int apps = 0;
            int matched = 0;
            String error = null;
            for (RepoResult r : results) {
                String rk = normalizeRepoUrl(r.url());
                if (!rk.equals(key) && !rk.startsWith(key + "/")) {
                    continue;
                }
                matched++;
                apps += r.apps();
                if (r.error() != null && error == null) {
                    error = r.error();
                }
            }
            if (matched > 0) {
                source.recordSync(now, apps, error);
                repos.save(source);
            }
        }
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

    /// HEAD of every task's remote, resolved in parallel. Null means "could not tell" — those
    /// always get a full scan, so the optimisation can never silently drop a repo.
    private List<String> currentHeads(List<ScanTask> tasks, ExecutorService pool) {
        if (!incrementalScan) {
            return tasks.stream().map(t -> (String) null).toList();
        }
        List<Future<String>> probes = tasks.stream()
                .map(t -> pool.submit(() -> repoFetch.remoteHead(t.scanUrl())))
                .toList();
        List<String> heads = new ArrayList<>();
        for (Future<String> probe : probes) {
            try {
                heads.add(probe.get());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                heads.add(null);
            } catch (ExecutionException e) {
                heads.add(null);
            }
        }
        return heads;
    }

    private boolean isUnchanged(ScanTask task, String head) {
        if (head == null) {
            return false;
        }
        return revisions.findById(normalizeRepoUrl(task.scanUrl()))
                .map(r -> head.equals(r.getCommitSha()))
                .orElse(false);
    }

    private void rememberHead(ScanTask task, String head) {
        if (head == null) {
            return;
        }
        String key = normalizeRepoUrl(task.scanUrl());
        revisions.findById(key).ifPresentOrElse(
                existing -> {
                    existing.update(head);
                    revisions.save(existing);
                },
                () -> revisions.save(new RepoRevisionEntity(key, head)));
    }

    private int runScans(List<ScanTask> tasks, List<RepoResult> repoResults, SyncListener listener,
                         Map<String, List<String>> undeclaredByApp,
                         Map<String, List<String>> driftByApp,
                         List<String> unchangedRepos) {
        if (tasks.isEmpty()) {
            return 0;
        }
        int threads = Math.max(1, Math.min(scanParallelism, tasks.size()));
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        int totalApps = 0;
        // Cloning a repo that has not moved since the last successful scan buys nothing, and on a
        // hundred-repo org it is most of the runtime. ls-remote costs one round trip to decide.
        List<String> heads = currentHeads(tasks, pool);
        try {
            List<Future<List<MuleScan>>> futures = new ArrayList<>();
            for (int i = 0; i < tasks.size(); i++) {
                ScanTask task = tasks.get(i);
                futures.add(isUnchanged(task, heads.get(i))
                        ? null
                        : pool.submit(() -> scanService.fetchAndScan(task.scanUrl())));
            }
            for (int i = 0; i < tasks.size(); i++) {
                ScanTask task = tasks.get(i);
                if (futures.get(i) == null) {
                    RepoResult unchanged = new RepoResult(task.displayUrl(), 0, List.of(), null);
                    repoResults.add(unchanged);
                    listener.repoFinished(unchanged);
                    unchangedRepos.add(task.displayUrl());
                    continue;
                }
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
                    rememberHead(task, heads.get(i));
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
                                    Map<String, List<String>> driftByApp,
                                    int unchanged) {
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
        if (unchanged > 0) {
            sb.append(unchanged).append(" repo(s) unchanged since the last sync — kept as they were. ");
        }
        if (totalApps == 0 && unchanged == 0 && !repos.isEmpty()) {
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
