package com.apiguard.core.blast;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;

class ManifestLoaderTest {

    @Test
    void discoverIgnoresBinaryAndUnrelatedFiles(@TempDir Path dir) throws IOException {
        Files.writeString(dir.resolve("apiguard-deps.yaml"),
                "consumer: orders-web\nowner_team: web\ndepends_on:\n  - api: orders-api\n");

        Path gitDir = Files.createDirectories(dir.resolve(".git"));
        Files.write(gitDir.resolve("index"), new byte[]{(byte) 0xC3, (byte) 0x28, (byte) 0xFF, 0x00, (byte) 0x80});
        Files.writeString(dir.resolve("README.md"), "# not a manifest\n");

        ManifestLoader.Loaded loaded = ManifestLoader.discover(dir);

        assertEquals(1, loaded.consumers().size());
        assertEquals("orders-web", loaded.consumers().get(0).consumer);
    }
}
