package com.apiguard.core.blast;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.util.List;

/**
 * A consumer's declared dependency on one or more producer APIs — the {@code apiguard-deps.yaml}
 * file each consumer commits to its own repo. This is the input that powers downstream blast radius.
 *
 * <pre>
 * consumer: orders-web
 * owner_team: web-checkout
 * reviewers: [ "gh:alice", "gh:bob" ]
 * slack_channel: "#checkout-alerts"
 * depends_on:
 *   - api: payments-api
 *     endpoints:
 *       - path: "GET /payments/{id}"
 *         fields: [ "status", "amount" ]
 * </pre>
 */
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
        /** the producer endpoint depended on, e.g. {@code "GET /payments/{id}"} */
        public String path;
        public List<String> fields = List.of();

        /**
         * The consumer's <i>own</i> inbound endpoint that makes this call (e.g. {@code "GET /orders/{id}"}),
         * when known from a scan. Null for hand-written or app-level (whole-API) dependencies. This is
         * what lets the tool answer "for this one endpoint, what does it call?" — the property-file view.
         */
        @JsonProperty("consumer_endpoint")
        public String consumerEndpoint;
    }
}
