package com.apiguard.server.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Base64;

@Component
public class CredentialCipher {

    private static final String TRANSFORM = "AES/GCM/NoPadding";
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final String PREFIX = "enc:v1:";

    private final SecretKeySpec key;
    private final SecureRandom rng = new SecureRandom();

    public CredentialCipher(
            @Value("${apiguard.security.encryption-key:${APIGUARD_ENCRYPTION_KEY:}}") String rawKey) {
        this.key = deriveKey(rawKey);
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
