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
