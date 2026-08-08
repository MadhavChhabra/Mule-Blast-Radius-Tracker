package com.apiguard.server;

import com.apiguard.server.repo.AnypointCredentialRepository;
import com.apiguard.server.service.CredentialStore;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
class CredentialStoreTest {

    @Autowired
    CredentialStore store;
    @Autowired
    AnypointCredentialRepository repo;

    @Test
    void savesSecretEncryptedThenReloadsIt() {
        store.clearAnypoint();
        store.saveAnypoint("cid-1", "super-secret-value", "org-9", "Sandbox");

        var raw = repo.findById(1).orElseThrow();
        assertTrue(raw.getClientSecret().startsWith("enc:v1:"), "secret must be stored encrypted");
        assertFalse(raw.getClientSecret().contains("super-secret-value"), "plaintext must not be at rest");

        var loaded = store.loadAnypoint().orElseThrow();
        assertEquals("cid-1", loaded.clientId());
        assertEquals("super-secret-value", loaded.clientSecret());
        assertEquals("org-9", loaded.orgId());
        assertEquals("Sandbox", loaded.environment());

        store.clearAnypoint();
        assertTrue(store.loadAnypoint().isEmpty(), "disconnect must remove the saved credential");
    }
}
