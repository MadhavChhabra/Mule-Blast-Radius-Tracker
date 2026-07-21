package com.apiguard.server.web;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.Classification;

import java.util.List;

public final class Dtos {

    private Dtos() {
    }

    public record ChangeDto(String classification, String kind, String endpoint,
                            String jsonPointer, String field, String description) {
        public static ChangeDto from(Change c) {
            return new ChangeDto(c.classification().name(), c.kind().name(), c.endpoint(),
                    c.jsonPointer(), c.field(), c.description());
        }
    }

    public record ConsumerDto(String consumer, String ownerTeam, List<String> reviewers,
                              String slackChannel, String sourceRepo, String matchedField,
                              String lastSeenAt, Boolean discoveredOnly) {
        public static ConsumerDto from(BlastRadiusResolver.ConsumerImpact c) {
            return new ConsumerDto(c.consumer(), c.ownerTeam(), c.reviewers(),
                    c.slackChannel(), c.sourceRepo(), c.matchedField(), null, null);
        }

        public static ConsumerDto from(BlastRadiusResolver.ConsumerImpact c,
                                       String lastSeenAt, Boolean discoveredOnly) {
            return new ConsumerDto(c.consumer(), c.ownerTeam(), c.reviewers(),
                    c.slackChannel(), c.sourceRepo(), c.matchedField(), lastSeenAt, discoveredOnly);
        }
    }

    public record UpstreamDto(String api, String endpoint, String field) {
        public static UpstreamDto from(BlastRadiusResolver.UpstreamRef u) {
            return new UpstreamDto(u.api(), u.endpoint(), u.field());
        }
    }

    public record ImpactDto(ChangeDto change, List<ConsumerDto> downstream, List<UpstreamDto> upstream) {
        public static ImpactDto from(BlastRadiusResolver.Impact i) {
            return new ImpactDto(
                    ChangeDto.from(i.change()),
                    i.downstream().stream().map(ConsumerDto::from).toList(),
                    i.upstream().stream().map(UpstreamDto::from).toList());
        }
    }

    public record SummaryDto(int total, long breaking, long safe, long additive, long impactedConsumers) {
        public static SummaryDto from(List<Change> changes, long impactedConsumers) {
            long breaking = changes.stream().filter(Change::isBreaking).count();
            long additive = changes.stream().filter(c -> c.classification() == Classification.ADDITIVE).count();
            return new SummaryDto(changes.size(), breaking, changes.size() - breaking - additive, additive, impactedConsumers);
        }
    }

    public record AdvisoryDto(String recommendedBump, String currentVersion, String nextVersion,
                              int riskScore, String riskLevel) {
    }

    public record AnalyzeResponse(String api, SummaryDto summary, AdvisoryDto advisory,
                                  List<ImpactDto> impacts, String changelog) {
    }

    public record ExplorerResponse(String api, String endpoint, String field,
                                   List<ConsumerDto> downstream, List<UpstreamDto> upstream) {
    }

    public record ChangelogDto(Long id, String api, String versionLabel, String markdown, String publishedAt) {
    }

    public record ManifestDto(String consumer, String ownerTeam, List<String> reviewers,
                              String slackChannel, String sourceRepo, List<EdgeDto> edges) {
    }

    public record EdgeDto(String api, String endpoint, String field) {
    }

    public record MuleCallDto(String api, String endpoint) {
    }

    public record MuleEndpointDto(String endpoint, List<MuleCallDto> calls) {
    }

    public record MuleScanDto(String app, String groupId, String version,
                              List<String> downstreamApis, List<MuleEndpointDto> endpoints,
                              List<String> declaredApis, List<String> undeclaredApis,
                              List<ConfigDriftDto> configDrift) {
    }

    public record ConfigDriftDto(String configName, String host, String unresolvedPlaceholder) {
    }

    public record ScanResultDto(int apps, List<MuleScanDto> scans) {
    }

    public record PropagationField(String endpoint, String field, int consumerCount,
                                   List<ConsumerDto> downstream, List<UpstreamDto> upstream) {
    }

    public record PropagationResponse(String api, String title, String version,
                                      int endpoints, int fields, int impactedFields, int impactedConsumers,
                                      List<PropagationField> items) {
    }

    public record EndpointProducer(String api, String layer, String endpoint, List<String> fields) {
    }

    public record EndpointConsumer(String consumer, String layer, String viaEndpoint, List<String> fields,
                                   String ownerTeam, List<String> reviewers, String slackChannel, String sourceRepo) {
    }

    public record EndpointInspectDto(String api, String layer, String endpoint, List<String> endpoints,
                                     List<EndpointProducer> calls, List<EndpointProducer> appLevelCalls,
                                     List<EndpointConsumer> calledBy) {
    }

    public record GraphNode(String id, String label, String layer, boolean api,
                            int dependsOn, int dependedOnBy, String ownerTeam, List<String> reviewers) {
    }

    public record GraphEdge(String from, String to, String label, String risk, List<String> via) {
    }

    public record GraphDto(List<GraphNode> nodes, List<GraphEdge> edges) {
    }
}
