package com.apiguard.server.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.PosixFilePermission;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;
import java.util.Set;

@Component
public class CredentialCipher {

    private static final Logger log = LoggerFactory.getLogger(CredentialCipher.class);

    private static final String TRANSFORM = "AES/GCM/NoPadding";
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final String PREFIX = "enc:v1:";

    private final SecretKeySpec key;
    private final SecureRandom rng = new SecureRandom();

    public CredentialCipher(
            @Value("${apiguard.security.encryption-key:${APIGUARD_ENCRYPTION_KEY:}}") String rawKey,
            @Value("${apiguard.security.key-file:${user.home}/.apiguard/credential.key}") String keyFile) {
        this.key = resolveKey(rawKey, keyFile);
    }

    private static SecretKeySpec resolveKey(String rawKey, String keyFile) {
        if (rawKey != null && !rawKey.isBlank()) {
            return deriveKey(rawKey);
        }
        if (keyFile == null || keyFile.isBlank()) {
            return null;
        }
        return deriveKey(loadOrCreateKeyFile(keyFile));
    }

    private static String loadOrCreateKeyFile(String keyFile) {
        try {
            Path kf = Path.of(keyFile);
            if (Files.isRegularFile(kf)) {
                String material = Files.readString(kf, StandardCharsets.UTF_8).trim();
                return material.isBlank() ? null : material;
            }
            byte[] rnd = new byte[32];
            new SecureRandom().nextBytes(rnd);
            String material = Base64.getEncoder().encodeToString(rnd);
            if (kf.getParent() != null) {
                Files.createDirectories(kf.getParent());
            }
            Files.writeString(kf, material, StandardCharsets.UTF_8);
            restrict(kf);
            log.info("Generated a local credential encryption key at {} (keep it safe — it protects your saved secrets).", kf);
            return material;
        } catch (Exception e) {
            log.warn("Could not manage a local encryption key file ({}); saved credentials will be disabled.", e.getMessage());
            return null;
        }
    }

    private static void restrict(Path file) {
        try {
            Files.setPosixFilePermissions(file, Set.of(PosixFilePermission.OWNER_READ, PosixFilePermission.OWNER_WRITE));
        } catch (Exception ignored) {
            // Non-POSIX (Windows) — the file inherits the user's home-dir ACL, which is already user-scoped.
        }
    }

    public boolean isConfigured() {
        return key != null;
    }

    public String encrypt(String plaintext) {
        if (plaintext == null) return null;
        if (key == null) {
            throw new IllegalStateException(
                    "apiguard.security.encryption-key is not set — cannot encrypt at rest.");
        }
        try {
            byte[] iv = new byte[IV_BYTES];
            rng.nextBytes(iv);
            Cipher c = Cipher.getInstance(TRANSFORM);
            c.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            byte[] ct = c.doFinal(plaintext.getBytes(StandardCharsets.UTF_8));
            byte[] out = new byte[iv.length + ct.length];
            System.arraycopy(iv, 0, out, 0, iv.length);
            System.arraycopy(ct, 0, out, iv.length, ct.length);
            return PREFIX + Base64.getEncoder().encodeToString(out);
        } catch (Exception e) {
            throw new IllegalStateException("encryption failed", e);
        }
    }

    public String decrypt(String ciphertext) {
        if (ciphertext == null) return null;
        if (!ciphertext.startsWith(PREFIX)) {
            return ciphertext;
        }
        if (key == null) {
            throw new IllegalStateException(
                    "encrypted value found but apiguard.security.encryption-key is not set.");
        }
        try {
            byte[] raw = Base64.getDecoder().decode(ciphertext.substring(PREFIX.length()));
            if (raw.length <= IV_BYTES) {
                throw new IllegalArgumentException("ciphertext too short");
            }
            byte[] iv = new byte[IV_BYTES];
            System.arraycopy(raw, 0, iv, 0, IV_BYTES);
            byte[] ct = new byte[raw.length - IV_BYTES];
            System.arraycopy(raw, IV_BYTES, ct, 0, ct.length);
            Cipher c = Cipher.getInstance(TRANSFORM);
            c.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, iv));
            return new String(c.doFinal(ct), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new IllegalStateException("decryption failed", e);
        }
    }

    private static SecretKeySpec deriveKey(String rawKey) {
        if (rawKey == null || rawKey.isBlank()) {
            return null;
        }
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            return new SecretKeySpec(md.digest(rawKey.getBytes(StandardCharsets.UTF_8)), "AES");
        } catch (Exception e) {
            throw new IllegalStateException("could not derive AES key", e);
        }
    }
}
