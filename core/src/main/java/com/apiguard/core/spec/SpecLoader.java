package com.apiguard.core.spec;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.parser.OpenAPIV3Parser;
import io.swagger.v3.parser.core.models.ParseOptions;
import io.swagger.v3.parser.core.models.SwaggerParseResult;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;

/**
 * Thin wrapper over swagger-parser that loads an OpenAPI 3.x document (YAML or JSON)
 * into the {@link OpenAPI} model with {@code $ref}s fully resolved.
 *
 * <p>We enable {@code resolveFully} so the {@link com.apiguard.core.diff.DiffEngine}
 * can compare inlined schemas without chasing references. We keep {@code flatten}
 * off because we want components inlined at their use sites, not re-extracted.
 */
public final class SpecLoader {

    private SpecLoader() {
    }

    private static ParseOptions options() {
        ParseOptions opts = new ParseOptions();
        opts.setResolve(true);        // resolve external + internal refs
        opts.setResolveFully(true);   // inline resolved schemas so diffing is structural
        opts.setResolveCombinators(false); // keep oneOf/anyOf/allOf visible to the engine
        return opts;
    }

    /** Load a spec from a file path (YAML or JSON, detected by content). */
    public static OpenAPI loadFile(Path path) {
        try {
            String content = Files.readString(path, StandardCharsets.UTF_8);
            return parse(content, path.toString());
        } catch (IOException e) {
            throw new SpecLoadException("Could not read spec file: " + path, e);
        }
    }

    /** Load a spec from an in-memory string (YAML or JSON). */
    public static OpenAPI loadString(String content) {
        return parse(content, "<string>");
    }

    private static OpenAPI parse(String content, String source) {
        // Exchange specs are often RAML; detect and convert to the OpenAPI model.
        if (RamlLoader.looksLikeRaml(content)) {
            return RamlLoader.loadString(content);
        }
        SwaggerParseResult result = new OpenAPIV3Parser().readContents(content, null, options());
        OpenAPI api = result.getOpenAPI();
        if (api == null) {
            List<String> messages = result.getMessages();
            throw new SpecLoadException("Failed to parse OpenAPI spec from " + source
                    + (messages == null || messages.isEmpty() ? "" : ": " + String.join("; ", messages)));
        }
        return api;
    }

    /** Thrown when a spec cannot be read or parsed. */
    public static final class SpecLoadException extends RuntimeException {
        public SpecLoadException(String message) {
            super(message);
        }

        public SpecLoadException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
