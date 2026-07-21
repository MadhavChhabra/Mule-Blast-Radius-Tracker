package com.apiguard.server;

import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.service.SourcesService;
import com.apiguard.server.service.SyncJobService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class SyncJobServiceTest {

    @Autowired
    SyncJobService job;
    @Autowired
    SourcesService sources;
    @Autowired
    AnypointCredentials creds;

    private static String sampleProjectPath() {
        for (Path base : new Path[]{Path.of("samples/mule/orders-exp-api"),
                Path.of("../samples/mule/orders-exp-api")}) {
            if (Files.isDirectory(base)) {
                return base.toAbsolutePath().toString();
            }
        }
        throw new IllegalStateException("sample Mule project not found");
    }

    @Test
    void backgroundSyncRunsToCompletionWithProgress() throws Exception {
        creds.clear();
        String path = sampleProjectPath();
        sources.addRepo(path);
        try {
            SyncJobService.Progress started = job.start();
            assertEquals("running", started.state());

            SyncJobService.Progress polled = started;
            long deadline = System.currentTimeMillis() + 30_000;
            while (!polled.state().equals("done") && !polled.state().equals("failed")) {
                assertTrue(System.currentTimeMillis() < deadline, "sync did not finish in 30s");
                Thread.sleep(100);
                polled = job.status();
            }

            final SyncJobService.Progress p = polled;
            assertEquals("done", p.state(), () -> "error: " + p.error());
            assertNotNull(p.result(), "terminal progress carries the full result");
            assertTrue(p.reposTotal() >= 1, "planned repo count was reported");
            assertTrue(p.repoResults().stream().anyMatch(r -> r.url().equals(path)),
                    "the registered repo shows in streamed results");
            assertTrue(p.result().repos().stream()
                            .anyMatch(r -> r.appNames().contains("orders-exp-api")),
                    () -> "apps: " + p.result().repos());
        } finally {
            sources.removeRepo(path);
        }
    }
}
