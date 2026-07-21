package com.apiguard.server.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

@Service
public class SyncJobService {

    private static final Logger log = LoggerFactory.getLogger(SyncJobService.class);

    public record Progress(String state, String phase, int reposDone, int reposTotal,
                           List<SourcesService.RepoResult> repoResults,
                           SourcesService.SyncAllResult result, String error,
                           long startedAt, long finishedAt) {

        static Progress idle() {
            return new Progress("idle", null, 0, 0, List.of(), null, null, 0, 0);
        }
    }

    private final SourcesService sources;
    private final ExecutorService runner = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "wakegraph-sync");
        t.setDaemon(true);
        return t;
    });
    private final Object lock = new Object();
    private volatile Progress progress = Progress.idle();
    private volatile boolean running = false;
    private volatile boolean cancelRequested = false;

    public SyncJobService(SourcesService sources) {
        this.sources = sources;
    }

    public Progress start() {
        synchronized (lock) {
            if (running) {
                return progress;
            }
            running = true;
            cancelRequested = false;
            long startedAt = System.currentTimeMillis();
            progress = new Progress("running", "Starting…", 0, 0, List.of(), null, null, startedAt, 0);
            runner.submit(() -> run(startedAt));
            return progress;
        }
    }

    public Progress cancel() {
        if (running) {
            cancelRequested = true;
            Progress p = progress;
            progress = new Progress("running", "Cancelling — finishing the current step…",
                    p.reposDone(), p.reposTotal(), p.repoResults(), null, null, p.startedAt(), 0);
        }
        return progress;
    }

    public Progress status() {
        return progress;
    }

    private void run(long startedAt) {
        List<SourcesService.RepoResult> live = new ArrayList<>();
        AtomicInteger total = new AtomicInteger();
        try {
            SourcesService.SyncAllResult result = sources.syncAll(new SourcesService.SyncListener() {
                @Override
                public void phase(String label) {
                    publish(label, live, total, startedAt);
                }

                @Override
                public void planned(int totalRepos) {
                    total.set(totalRepos);
                    publish(progress.phase(), live, total, startedAt);
                }

                @Override
                public void repoFinished(SourcesService.RepoResult repoResult) {
                    synchronized (live) {
                        live.add(repoResult);
                    }
                    publish(progress.phase(), live, total, startedAt);
                }

                @Override
                public boolean isCancelled() {
                    return cancelRequested;
                }
            });
            progress = new Progress("done", cancelRequested ? "Cancelled — partial results kept" : "Done",
                    snapshot(live).size(), total.get(),
                    snapshot(live), result, null, startedAt, System.currentTimeMillis());
        } catch (Exception e) {
            log.warn("Background sync failed: {}", e.getMessage(), e);
            progress = new Progress("failed", "Failed", snapshot(live).size(), total.get(),
                    snapshot(live), null,
                    e.getMessage() == null ? "sync failed" : e.getMessage(),
                    startedAt, System.currentTimeMillis());
        } finally {
            running = false;
        }
    }

    private void publish(String phase, List<SourcesService.RepoResult> live, AtomicInteger total, long startedAt) {
        List<SourcesService.RepoResult> copy = snapshot(live);
        progress = new Progress("running", phase, copy.size(), total.get(), copy, null, null, startedAt, 0);
    }

    private static List<SourcesService.RepoResult> snapshot(List<SourcesService.RepoResult> live) {
        synchronized (live) {
            return List.copyOf(live);
        }
    }
}
