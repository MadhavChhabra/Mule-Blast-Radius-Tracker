package com.apiguard.core.spec;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.Operation;
import io.swagger.v3.oas.models.PathItem;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.media.Content;
import io.swagger.v3.oas.models.media.MediaType;
import io.swagger.v3.oas.models.media.Schema;
import io.swagger.v3.oas.models.parameters.Parameter;
import io.swagger.v3.oas.models.parameters.RequestBody;
import io.swagger.v3.oas.models.responses.ApiResponse;
import io.swagger.v3.oas.models.responses.ApiResponses;
import io.swagger.v3.oas.models.security.SecurityRequirement;
import org.raml.v2.api.RamlModelBuilder;
import org.raml.v2.api.RamlModelResult;
import org.raml.v2.api.model.v10.api.Api;
import org.raml.v2.api.model.v10.bodies.Response;
import org.raml.v2.api.model.v10.datamodel.ArrayTypeDeclaration;
import org.raml.v2.api.model.v10.datamodel.BooleanTypeDeclaration;
import org.raml.v2.api.model.v10.datamodel.IntegerTypeDeclaration;
import org.raml.v2.api.model.v10.datamodel.NumberTypeDeclaration;
import org.raml.v2.api.model.v10.datamodel.ObjectTypeDeclaration;
import org.raml.v2.api.model.v10.datamodel.StringTypeDeclaration;
import org.raml.v2.api.model.v10.datamodel.TypeDeclaration;
import org.raml.v2.api.model.v10.methods.Method;
import org.raml.v2.api.model.v10.resources.Resource;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Loads a RAML 1.0 spec and converts it into the swagger {@link OpenAPI} model, so the existing
 * {@link com.apiguard.core.diff.DiffEngine} and all its rules apply unchanged. Exchange REST assets
 * are usually RAML, so this is what makes breaking-change detection work on a MuleSoft estate.
 *
 * <p>Covers the constructs the diff engine reasons about: resources → paths, methods → operations,
 * URI/query parameters (with required-ness), request bodies, responses, and object/array/enum/scalar
 * types (nested). Richer RAML (traits, resource types, unions) is resolved by the parser before we
 * walk it.
 */
public final class RamlLoader {

    private RamlLoader() {
    }

    static boolean looksLikeRaml(String content) {
        return content != null && content.stripLeading().startsWith("#%RAML");
    }

    public static OpenAPI loadString(String content) {
        return convert(new RamlModelBuilder().buildApi(content, "raml"));
    }

    /**
     * Load a RAML file from disk, resolving its {@code !include}s relative to the file's location.
     * This is what makes an unzipped Exchange asset (root RAML + library/type includes) parseable.
     */
    public static OpenAPI loadFile(java.nio.file.Path ramlFile) {
        return convert(new RamlModelBuilder().buildApi(ramlFile.toFile()));
    }

    private static OpenAPI convert(RamlModelResult result) {
        if (result.hasErrors()) {
            List<String> msgs = new ArrayList<>();
            result.getValidationResults().forEach(v -> msgs.add(v.getMessage()));
            throw new SpecLoader.SpecLoadException("Invalid RAML: " + String.join("; ", msgs));
        }
        Api api = result.getApiV10();
        if (api == null) {
            throw new SpecLoader.SpecLoadException("Only RAML 1.0 is supported for diffing (got RAML 0.8).");
        }

        OpenAPI oapi = new OpenAPI();
        oapi.setInfo(new Info()
                .title(api.title() != null ? api.title().value() : "RAML API")
                .version(api.version() != null ? api.version().value() : "1.0.0"));

        io.swagger.v3.oas.models.Paths paths = new io.swagger.v3.oas.models.Paths();
        for (Resource resource : api.resources()) {
            addResource(resource, paths);
        }
        oapi.setPaths(paths);
        return oapi;
    }

    private static void addResource(Resource resource, io.swagger.v3.oas.models.Paths paths) {
        if (!resource.methods().isEmpty()) {
            PathItem item = new PathItem();
            for (Method method : resource.methods()) {
                item.operation(httpMethod(method.method()), toOperation(resource, method));
            }
            paths.addPathItem(resource.resourcePath(), item);
        }
        for (Resource child : resource.resources()) {
            addResource(child, paths);
        }
    }

    private static Operation toOperation(Resource resource, Method method) {
        Operation op = new Operation();

        // Path parameters (from the resource) + query parameters (from the method).
        for (TypeDeclaration up : resource.uriParameters()) {
            op.addParametersItem(toParameter(up, "path", true));
        }
        for (TypeDeclaration qp : method.queryParameters()) {
            op.addParametersItem(toParameter(qp, "query", qp.required()));
        }

        // Request body (application/json).
        Schema<?> reqSchema = jsonSchema(method.body());
        if (reqSchema != null) {
            op.setRequestBody(new RequestBody().required(true).content(jsonContent(reqSchema)));
        }

        // Responses.
        ApiResponses responses = new ApiResponses();
        for (Response response : method.responses()) {
            String code = response.code() != null ? response.code().value() : "200";
            ApiResponse ar = new ApiResponse().description(code);
            Schema<?> respSchema = jsonSchema(response.body());
            if (respSchema != null) {
                ar.setContent(jsonContent(respSchema));
            }
            responses.addApiResponse(code, ar);
        }
        if (responses.isEmpty()) {
            responses.addApiResponse("200", new ApiResponse().description("OK"));
        }
        op.setResponses(responses);

        // Security (securedBy at the method level → auth required).
        if (method.securedBy() != null && !method.securedBy().isEmpty()
                && method.securedBy().get(0) != null && method.securedBy().get(0).securityScheme() != null) {
            op.addSecurityItem(new SecurityRequirement().addList(method.securedBy().get(0).securityScheme().name()));
        }
        return op;
    }

    private static Parameter toParameter(TypeDeclaration td, String in, boolean required) {
        return new Parameter()
                .name(td.name())
                .in(in)
                .required(required)
                .schema(toSchema(td));
    }

    /** Pick the application/json body from a list of media-type bodies and build its schema. */
    private static Schema<?> jsonSchema(List<TypeDeclaration> bodies) {
        if (bodies == null || bodies.isEmpty()) {
            return null;
        }
        TypeDeclaration chosen = null;
        for (TypeDeclaration b : bodies) {
            if (b.name() != null && b.name().toLowerCase().contains("json")) {
                chosen = b;
                break;
            }
        }
        if (chosen == null) {
            chosen = bodies.get(0);
        }
        return toSchema(chosen);
    }

    private static Content jsonContent(Schema<?> schema) {
        return new Content().addMediaType("application/json", new MediaType().schema(schema));
    }

    /** Recursively convert a RAML type declaration to a swagger schema. */
    private static Schema<?> toSchema(TypeDeclaration td) {
        Schema<Object> schema = new Schema<>();
        if (td instanceof ObjectTypeDeclaration obj) {
            schema.setType("object");
            Map<String, Schema> props = new LinkedHashMap<>();
            List<String> required = new ArrayList<>();
            for (TypeDeclaration prop : obj.properties()) {
                props.put(prop.name(), toSchema(prop));
                if (prop.required()) {
                    required.add(prop.name());
                }
            }
            if (!props.isEmpty()) {
                schema.setProperties(props);
            }
            if (!required.isEmpty()) {
                schema.setRequired(required);
            }
        } else if (td instanceof ArrayTypeDeclaration arr) {
            schema.setType("array");
            if (arr.items() != null) {
                schema.setItems(toSchema(arr.items()));
            }
        } else if (td instanceof StringTypeDeclaration str) {
            schema.setType("string");
            if (str.enumValues() != null && !str.enumValues().isEmpty()) {
                schema.setEnum(new ArrayList<>(str.enumValues()));
            }
        } else if (td instanceof IntegerTypeDeclaration) {
            schema.setType("integer");
        } else if (td instanceof NumberTypeDeclaration) {
            schema.setType("number");
        } else if (td instanceof BooleanTypeDeclaration) {
            schema.setType("boolean");
        } else {
            schema.setType(mapScalar(td.type()));
        }
        return schema;
    }

    private static String mapScalar(String ramlType) {
        if (ramlType == null) {
            return "string";
        }
        return switch (ramlType) {
            case "integer" -> "integer";
            case "number" -> "number";
            case "boolean" -> "boolean";
            case "array" -> "array";
            case "object" -> "object";
            default -> "string"; // string, date-only, datetime, file, or a named type fallback
        };
    }

    private static PathItem.HttpMethod httpMethod(String raml) {
        return PathItem.HttpMethod.valueOf(raml.toUpperCase());
    }
}
