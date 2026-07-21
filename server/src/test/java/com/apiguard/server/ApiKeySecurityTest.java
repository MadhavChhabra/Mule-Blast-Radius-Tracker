package com.apiguard.server;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "apiguard.security.api-key=test-secret-key")
class ApiKeySecurityTest {

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    private String url(String path) {
        return "http://localhost:" + port + path;
    }

    @Test
    void anonymousIsRejected() {
        ResponseEntity<String> r = rest.getForEntity(url("/api/graph"), String.class);
        assertEquals(HttpStatus.UNAUTHORIZED, r.getStatusCode());
    }

    @Test
    void apiKeyHeaderIsAccepted() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("X-API-Key", "test-secret-key");
        ResponseEntity<String> r = rest.exchange(url("/api/graph"), HttpMethod.GET,
                new HttpEntity<>(headers), String.class);
        assertEquals(HttpStatus.OK, r.getStatusCode());
    }

    @Test
    void bearerTokenIsAccepted() {
        HttpHeaders headers = new HttpHeaders();
        headers.setBearerAuth("test-secret-key");
        ResponseEntity<String> r = rest.exchange(url("/api/graph"), HttpMethod.GET,
                new HttpEntity<>(headers), String.class);
        assertEquals(HttpStatus.OK, r.getStatusCode());
    }

    @Test
    void wrongKeyIsRejected() {
        HttpHeaders headers = new HttpHeaders();
        headers.set("X-API-Key", "wrong");
        ResponseEntity<String> r = rest.exchange(url("/api/graph"), HttpMethod.GET,
                new HttpEntity<>(headers), String.class);
        assertEquals(HttpStatus.UNAUTHORIZED, r.getStatusCode());
    }

    @Test
    void healthStaysOpenForLivenessProbes() {
        ResponseEntity<String> r = rest.getForEntity(url("/api/health"), String.class);
        assertEquals(HttpStatus.OK, r.getStatusCode());
    }

    @Test
    void healthReportsAuthRequiredWhenKeyConfigured() {
        ResponseEntity<String> r = rest.getForEntity(url("/api/health"), String.class);
        assertEquals(HttpStatus.OK, r.getStatusCode());
        assertTrue(r.getBody() != null && r.getBody().contains("\"authRequired\":true"));
    }
}
