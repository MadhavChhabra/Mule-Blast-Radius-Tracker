package com.apiguard.server.web;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.Classification;
import com.apiguard.core.diff.Remediation;

import java.util.List;

public final class Dtos {

    private Dtos() {
    }

    public record ChangeDto(String classification, String kind, String endpoint,
                            String jsonPointer, String field, String description, String remediation) {
        public static ChangeDto from(Change c) {
            return new ChangeDto(c.classification().name(), c.kind().name(), c.endpoint(),
                    c.jsonPointer(), c.field(), c.description(), Remediation.forChange(c));
        }
    }

    public record ConsumerDto(String consumer, String ownerTeam, List<String> reviewers,
                              String slackChannel, String sourceRepo, String matchedField,
                              boolean fieldConfirmed, String lastSeenAt, Boolean discoveredOnly) {
        public static ConsumerDto from(BlastRadiusResolver.ConsumerImpact c) {
            return new ConsumerDto(c.consumer(), c.ownerTeam(), c.reviewers(),
                    c.slackChannel(), c.sourceRepo(), c.matchedField(), c.fieldConfirmed(), null, null);
        }

        public static ConsumerDto from(BlastRadiusResolver.ConsumerImpact c,
                                       String lastSeenAt, Boolean discoveredOnly) {
            return new ConsumerDto(c.consumer(), c.ownerTeam(), c.reviewers(),
                    c.slackChannel(), c.sourceRepo(), c.matchedField(), c.fieldConfirmed(),
                    lastSeenAt, discoveredOnly);
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
                              String slackChannel, String sourceRepo, List<EdgeDto> edges,
                              String updatedAt, Boolean discoveredOnly) {
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

    /// `confirmedCount` is the subset of `consumerCount` where discovered lineage proves the
    /// consumer reads this field; the rest are consumers we have no field-level data for.
    /// `side` is "response" (consumers read this field) or "request" (callers must send it).
    public record PropagationField(String endpoint, String field, String side,
                                   int consumerCount, int confirmedCount,
                                   List<ConsumerDto> downstream, List<UpstreamDto> upstream) {
    }

    public record PropagationResponse(String api, String title, String version,
                                      int endpoints, int fields, int impactedFields, int impactedConsumers,
                                      int unknownConsumers, List<PropagationField> items) {
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

    public record GraphEdge(String from, String to, String label, String risk, List<String> via,
                            boolean endpointLevel, boolean fieldLevel) {
    }

    /// How much of the estate is understood well enough to answer a field-level question.
    /// An Anypoint contract only proves app-to-app; endpoint and field detail come from repo scans,
    /// so this is the number that tells a user what registering more repos would buy them.
    public record GraphCoverage(int dependencies, int endpointLevel, int fieldLevel) {
    }

    public record GraphDto(List<GraphNode> nodes, List<GraphEdge> edges, GraphCoverage coverage) {
    }

    /// Who is downwind of an API: `direct` consumers call it, `transitive` are further out and
    /// affected only if their own providers pass the change along — worth telling, not blaming.
    public record ReachDto(String api, List<String> direct, List<String> transitive) {
    }
}
