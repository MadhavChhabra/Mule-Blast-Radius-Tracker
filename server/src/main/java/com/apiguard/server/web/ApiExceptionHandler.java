package com.apiguard.server.web;

import com.apiguard.core.spec.SpecLoader;
import com.apiguard.server.anypoint.AnypointClient;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.RestClientException;

import java.util.Map;
import java.util.NoSuchElementException;

@RestControllerAdvice
public class ApiExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(ApiExceptionHandler.class);

    private static ResponseEntity<Map<String, String>> error(HttpStatus status, String message) {
        return ResponseEntity.status(status).body(Map.of("error", message));
    }

    @ExceptionHandler({SpecLoader.SpecLoadException.class, IllegalArgumentException.class})
    public ResponseEntity<Map<String, String>> badRequest(RuntimeException e) {
        return error(HttpStatus.BAD_REQUEST, e.getMessage() == null ? "bad request" : e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Map<String, String>> invalidBody(MethodArgumentNotValidException e) {
        var fieldError = e.getBindingResult().getFieldError();
        String message = fieldError == null
                ? "Request validation failed."
                : (fieldError.getField() + " " + fieldError.getDefaultMessage());
        return error(HttpStatus.BAD_REQUEST, message);
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<Map<String, String>> unreadable(HttpMessageNotReadableException e) {
        return error(HttpStatus.BAD_REQUEST, "Malformed request body.");
    }

    @ExceptionHandler(NoSuchElementException.class)
    public ResponseEntity<Map<String, String>> notFound(NoSuchElementException e) {
        return error(HttpStatus.NOT_FOUND, e.getMessage() == null ? "Not found." : e.getMessage());
    }

    @ExceptionHandler(AnypointClient.AnypointException.class)
    public ResponseEntity<Map<String, String>> anypoint(RuntimeException e) {
        return error(HttpStatus.BAD_GATEWAY, e.getMessage() == null ? "Anypoint error" : e.getMessage());
    }

    @ExceptionHandler(RestClientException.class)
    public ResponseEntity<Map<String, String>> upstream(RestClientException e) {
        return error(HttpStatus.BAD_GATEWAY, "Upstream request failed: " + e.getMessage());
    }

    // Catch-all for unexpected server faults: uniform JSON, a real log line, and no
    // internal detail leaked to the client. Limited to RuntimeException so Spring's own
    // routing exceptions (unmatched paths, unsupported methods) keep their proper status.
    @ExceptionHandler(RuntimeException.class)
    public ResponseEntity<Map<String, String>> unexpected(RuntimeException e) {
        log.error("Unhandled server error", e);
        return error(HttpStatus.INTERNAL_SERVER_ERROR, "Unexpected server error.");
    }
}
