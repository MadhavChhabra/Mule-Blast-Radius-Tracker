package com.apiguard.server.service;

import com.apiguard.server.config.CredentialCipher;
import com.apiguard.server.domain.AnypointCredentialEntity;
import com.apiguard.server.repo.AnypointCredentialRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.Optional;

@Service
public class CredentialStore {

    private static final Logger log = LoggerFactory.getLogger(CredentialStore.class);
    private static final int ROW_ID = 1;

    private final AnypointCredentialRepository repo;
    private final CredentialCipher cipher;
    private final boolean persist;

    public CredentialStore(AnypointCredentialRepository repo, CredentialCipher cipher,
                           @Value("${apiguard.anypoint.persist:true}") boolean persist) {
        this.repo = repo;
        this.cipher = cipher;
        this.persist = persist;
    }

    public record StoredCreds(String clientId, String clientSecret, String orgId, String environment) {
    }

    @Transactional
    public void saveAnypoint(String clientId, String clientSecret, String orgId, String environment) {
        if (!persist) {
            return;
        }
        if (!cipher.isConfigured()) {
            log.warn("Anypoint credentials were not saved for next time — no encryption key is available. "
                    + "Set APIGUARD_ENCRYPTION_KEY (or let the desktop app manage a local key file) to persist them.");
            return;
        }
        AnypointCredentialEntity e = repo.findById(ROW_ID).orElseGet(() -> new AnypointCredentialEntity(ROW_ID));
        e.setClientId(clientId);
        e.setClientSecret(cipher.encrypt(clientSecret));
        e.setOrgId(orgId);
        e.setEnvironment(environment);
        e.setUpdatedAt(Instant.now());
        repo.save(e);
    }

    @Transactional(readOnly = true)
    public Optional<StoredCreds> loadAnypoint() {
        if (!persist) {
            return Optional.empty();
        }
        return repo.findById(ROW_ID).map(e -> new StoredCreds(
                e.getClientId(), safeDecrypt(e.getClientSecret()), e.getOrgId(), e.getEnvironment()));
    }

    @Transactional
    public void clearAnypoint() {
        repo.deleteById(ROW_ID);
    }

    private String safeDecrypt(String value) {
        try {
            return cipher.decrypt(value);
        } catch (RuntimeException e) {
            log.warn("Stored Anypoint secret could not be decrypted (encryption key changed?) — "
                    + "you will need to reconnect Anypoint once.");
            return null;
        }
    }
}
