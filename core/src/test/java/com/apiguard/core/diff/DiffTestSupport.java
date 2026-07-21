package com.apiguard.core.diff;

import com.apiguard.core.spec.SpecLoader;
import io.swagger.v3.oas.models.OpenAPI;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

final class DiffTestSupport {

    private DiffTestSupport() {
    }

    static OpenAPI spec(String body) {
        String doc = """
                openapi: 3.0.3
                info:
                  title: Test API
                  version: 1.0.0
                """ + body;
        return SpecLoader.loadString(doc);
    }

    static List<Change> diff(String oldBody, String newBody) {
        return new DiffEngine().diff(spec(oldBody), spec(newBody));
    }

    static Change single(List<Change> changes, ChangeKind kind) {
        List<Change> matches = changes.stream().filter(c -> c.kind() == kind).toList();
        assertEquals(1, matches.size(),
                () -> "Expected exactly one " + kind + " but got: " + changes);
        return matches.get(0);
    }

    static void assertHasKind(List<Change> changes, ChangeKind kind, Classification classification) {
        Change c = single(changes, kind);
        assertEquals(classification, c.classification(),
                () -> kind + " should be " + classification + " but was " + c.classification());
    }

    static void assertNoBreaking(List<Change> changes) {
        List<Change> breaking = changes.stream().filter(Change::isBreaking).toList();
        assertTrue(breaking.isEmpty(), () -> "Expected no breaking changes but found: " + breaking);
    }
}
