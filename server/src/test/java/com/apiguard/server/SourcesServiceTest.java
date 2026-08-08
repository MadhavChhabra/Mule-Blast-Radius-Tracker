package com.apiguard.server;

import com.apiguard.server.anypoint.AnypointCredentials;
import com.apiguard.server.repo.ScanSourceRepository;
import com.apiguard.server.service.SourcesService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class SourcesServiceTest {

    @Autowired
    SourcesService sources;
    @Autowired
    ScanSourceRepository repoRepository;
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
    void aTokenInTheRepoUrlIsStoredEncryptedAndNeverReturned() {

        String withToken = "https://ghp_secrettoken123@github.com/acme/private-repo.git";
        var status = sources.addRepo(withToken);

        String clean = "https://github.com/acme/private-repo.git";
        assertTrue(status.repos().contains(clean), status.repos().toString());
        assertTrue(status.repos().stream().noneMatch(r -> r.contains("ghp_secrettoken123")),
                "the token must never come back over the API: " + status.repos());

        var stored = repoRepository.findByUrl(clean).orElseThrow();
        assertTrue(stored.getUrl().equals(clean), stored.getUrl());
        org.junit.jupiter.api.Assertions.assertNotNull(stored.getCredential());
        assertTrue(!stored.getCredential().contains("ghp_secrettoken123"),
                "the credential column must be encrypted, not plaintext");

        // Removing by the clean URL (the only one the user can see) must work.
        sources.removeRepo(clean);
        assertTrue(repoRepository.findByUrl(clean).isEmpty());
    }

    @Test
    void duplicateRepoUrlsNormalizeToTheSameKey() {

        String viaOrg = SourcesService.normalizeRepoUrl("https://github.com/Acme/Orders-Exp-API.git");
        String direct = SourcesService.normalizeRepoUrl("https://tok@github.com/acme/orders-exp-api/");
        org.junit.jupiter.api.Assertions.assertEquals(viaOrg, direct);
        org.junit.jupiter.api.Assertions.assertNotEquals(viaOrg,
                SourcesService.normalizeRepoUrl("https://github.com/acme/orders-sapi"));
    }

    @Test
    void syncEverythingScansRegisteredRepos() {

        creds.clear();
        String path = sampleProjectPath();
        sources.addRepo(path);
        assertTrue(sources.status().repos().contains(path), "repo is registered");

        SourcesService.SyncAllResult result = sources.syncAll();

        var repo = result.repos().stream().filter(r -> r.url().equals(path)).findFirst().orElseThrow();
        assertTrue(repo.error() == null, () -> "scan error: " + repo.error());
        assertTrue(repo.appNames().contains("orders-exp-api"), () -> "apps: " + repo.appNames());

        sources.removeRepo(path);
    }
}
