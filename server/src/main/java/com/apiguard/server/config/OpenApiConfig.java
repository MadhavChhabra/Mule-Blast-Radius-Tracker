package com.apiguard.server.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.info.BuildProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/// Names BlipRadius' own REST API in the generated docs, so anyone wiring it into CI sees what
/// they are actually calling instead of springdoc's "OpenAPI definition v0" placeholder.
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI blipRadiusOpenApi(ObjectProvider<BuildProperties> buildProperties) {
        BuildProperties build = buildProperties.getIfAvailable();
        return new OpenAPI().info(new Info()
                .title("BlipRadius API")
                .version(build != null && build.getVersion() != null ? build.getVersion() : "0.1.0")
                .description("Change impact across a MuleSoft estate: dependency graph, "
                        + "field-level blast radius, breaking-change analysis and changelogs."));
    }
}
