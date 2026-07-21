package com.apiguard.server;

import com.apiguard.server.config.CredentialCipher;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CredentialCipherTest {

    @Test
    void roundTripEncryptsThenDecrypts() {
        CredentialCipher c = new CredentialCipher("test-key-please-change");
        String secret = "client-secret-42";
        String enc = c.encrypt(secret);
        assertTrue(enc.startsWith("enc:v1:"), enc);
        assertNotEquals(secret, enc);
        assertEquals(secret, c.decrypt(enc));
    }

    @Test
    void encryptionIsNondeterministic() {
        CredentialCipher c = new CredentialCipher("test-key-please-change");
        String a = c.encrypt("same-input");
        String b = c.encrypt("same-input");
        assertNotEquals(a, b, "AES-GCM must be nondeterministic (random IV)");
        assertEquals("same-input", c.decrypt(a));
        assertEquals("same-input", c.decrypt(b));
    }

    @Test
    void decryptPassesThroughValuesWithoutPrefix() {
        CredentialCipher c = new CredentialCipher("test-key-please-change");
        assertEquals("plain", c.decrypt("plain"));
        assertNull(c.decrypt(null));
    }

    @Test
    void unconfiguredCipherRefusesToEncryptButDoesNotBreakPlainReads() {
        CredentialCipher c = new CredentialCipher("");
        assertFalse(c.isConfigured());
        assertThrows(IllegalStateException.class, () -> c.encrypt("x"));
        assertEquals("plain", c.decrypt("plain"));
        assertThrows(IllegalStateException.class, () -> c.decrypt("enc:v1:AAAA"));
    }

    @Test
    void wrongKeyFailsToDecrypt() {
        String enc = new CredentialCipher("key-a").encrypt("payload");
        assertThrows(IllegalStateException.class,
                () -> new CredentialCipher("key-b").decrypt(enc));
    }
}
