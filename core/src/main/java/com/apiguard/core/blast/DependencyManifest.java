package com.apiguard.core.blast;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

@JsonIgnoreProperties(ignoreUnknown = true)
public class DependencyManifest {

    public String consumer;

    @JsonProperty("owner_team")
    public String ownerTeam;

    public List<String> reviewers = List.of();

    @JsonProperty("slack_channel")
    public String slackChannel;

    @JsonProperty("source_repo")
    public String sourceRepo;

    @JsonProperty("depends_on")
    public List<ApiDependency> dependsOn = List.of();

    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class ApiDependency {
        public String api;
        public List<EndpointDependency> endpoints = List.of();
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    public static class EndpointDependency {

        public String path;
        public List<String> fields = List.of();

        @JsonProperty("consumer_endpoint")
        public String consumerEndpoint;
    }
}
