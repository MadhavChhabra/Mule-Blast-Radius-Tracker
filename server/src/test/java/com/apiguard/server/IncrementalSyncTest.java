package com.apiguard.server;

import com.apiguard.server.domain.ScanSourceEntity;
import com.apiguard.server.repo.ScanSourceRepository;
import com.apiguard.server.service.RepoFetchService;
import com.apiguard.server.service.SourcesService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.SpyBean;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doReturn;

/// The two sync behaviours that only show up on the *second* run: a repo that has not moved is not
/// re-cloned, and a token left in a legacy row is moved out of the URL on startup. Both were
/// previously only reasoned about, never executed.
@SpringBootTest
class IncrementalSyncTest {

    @Autowired
    SourcesService sources;
    @Autowired
    ScanSourceRepository repoRepository;

    /// Only `remoteHead` is stubbed — fetching and scanning stay real, so the local sample project
    /// is genuinely scanned on the first pass.
    @SpyBean
    RepoFetchService repoFetch;

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
    void aRepoThatHasNotMovedIsNotRescannedOnTheSecondSync() {

        String path = sampleProjectPath();
        sources.addRepo(path);
        // A stable head means "nothing changed here since last time".
        doReturn("d34db33fd34db33fd34db33fd34db33fd34db33f").when(repoFetch).remoteHead(anyString());

        var first = sources.syncAll();
        assertEquals(0, first.unchangedRepos(),
                "nothing can be unchanged before the first successful scan");
        assertTrue(first.repos().stream().anyMatch(r -> r.error() == null && r.apps() > 0),
                "the first sync must actually scan the project: " + first.repos());

        var second = sources.syncAll();
        assertEquals(1, second.unchangedRepos(),
                "the same head must skip the clone on the second sync");
        assertTrue(second.repos().stream().allMatch(r -> r.apps() == 0 && r.error() == null),
                "a skipped repo reports no apps and no error: " + second.repos());

        // Moving the head puts the repo back in the queue rather than pinning it forever.
        doReturn("0000000feedfacefeedfacefeedfacefeedface0").when(repoFetch).remoteHead(anyString());
        var third = sources.syncAll();
        assertEquals(0, third.unchangedRepos(), "a new head must force a rescan");
        assertTrue(third.repos().stream().anyMatch(r -> r.apps() > 0), third.repos().toString());

        sources.removeRepo(path);
    }

    @Test
    void aHeadThatCannotBeReadFallsBackToScanning() {

        String path = sampleProjectPath();
        sources.addRepo(path);
        doReturn("cafebabecafebabecafebabecafebabecafebabe").when(repoFetch).remoteHead(anyString());
        sources.syncAll();

        // An unreachable remote (offline, auth expired) must not be mistaken for "unchanged" —
        // failing safe here means a slower sync, failing open means a silently stale estate.
        doReturn(null).when(repoFetch).remoteHead(anyString());
        var after = sources.syncAll();
        assertEquals(0, after.unchangedRepos(), "an unknown head must never count as unchanged");

        sources.removeRepo(path);
    }

    @Test
    void aLegacyRowWithATokenInTheUrlIsMigratedOnStartup() {

        // Written the way rows looked before the credential column existed.
        String legacy = "https://ghp_legacytoken999@github.com/acme/legacy-repo.git";
        repoRepository.save(new ScanSourceEntity(legacy));

        sources.migrateStoredCredentials();

        String clean = "https://github.com/acme/legacy-repo.git";
        var row = repoRepository.findByUrl(clean).orElseThrow(
                () -> new AssertionError("the URL should have been rewritten without the token"));
        assertFalse(row.getUrl().contains("ghp_legacytoken999"),
                "no plaintext token may survive in the URL: " + row.getUrl());
        assertNotNull(row.getCredential(), "the token should have been kept, encrypted");
        assertFalse(row.getCredential().contains("ghp_legacytoken999"),
                "the credential column must be encrypted, not moved in plaintext");

        // And the API never shows it either.
        assertTrue(sources.status().repos().stream().noneMatch(r -> r.contains("ghp_legacytoken999")),
                sources.status().repos().toString());

        // Idempotent: a second pass over already-clean rows changes nothing.
        sources.migrateStoredCredentials();
        var again = repoRepository.findByUrl(clean).orElseThrow();
        assertEquals(row.getCredential(), again.getCredential());
        assertEquals(clean, again.getUrl());

        sources.removeRepo(clean);
    }
}
