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

public final class SpecLoader {

    private SpecLoader() {
    }

    private static ParseOptions options() {
        ParseOptions opts = new ParseOptions();
        opts.setResolve(true);
        opts.setResolveFully(true);
        opts.setResolveCombinators(false);
        return opts;
    }

    public static OpenAPI loadFile(Path path) {
        try {
            String content = Files.readString(path, StandardCharsets.UTF_8);
            return parse(content, path.toString());
        } catch (IOException e) {
            throw new SpecLoadException("Could not read spec file: " + path, e);
        }
    }

    public static OpenAPI loadString(String content) {
        return parse(content, "<string>");
    }

    private static OpenAPI parse(String content, String source) {

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

    public static final class SpecLoadException extends RuntimeException {
        public SpecLoadException(String message) {
            super(message);
        }

        public SpecLoadException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
