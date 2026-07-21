package com.apiguard.core.blast;

import com.apiguard.core.diff.Change;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

public final class BlastRadiusResolver {

    private record Edge(String api, String endpoint, Set<String> fields, ConsumerImpact consumer) {
    }

    private final List<Edge> edges = new ArrayList<>();
    private final List<FieldSourceManifest.Source> upstream = new ArrayList<>();
    private final List<String> upstreamApis = new ArrayList<>();

    public BlastRadiusResolver(List<DependencyManifest> consumers, List<FieldSourceManifest> sources) {
        for (DependencyManifest m : consumers) {
            ConsumerImpact ref = new ConsumerImpact(m.consumer, m.ownerTeam,
                    List.copyOf(m.reviewers == null ? List.of() : m.reviewers), m.slackChannel, m.sourceRepo, null);
            for (DependencyManifest.ApiDependency dep : nullSafe(m.dependsOn)) {
                for (DependencyManifest.EndpointDependency ep : nullSafe(dep.endpoints)) {
                    edges.add(new Edge(dep.api, ep.path,
                            new LinkedHashSet<>(nullSafe(ep.fields)), ref));
                }
            }
        }
        for (FieldSourceManifest s : sources) {
            for (FieldSourceManifest.Source src : nullSafe(s.sources)) {
                upstream.add(src);
                upstreamApis.add(s.api);
            }
        }
    }

    public List<Impact> resolve(String apiName, List<Change> changes) {
        List<Impact> impacts = new ArrayList<>();
        for (Change change : changes) {
            List<ConsumerImpact> down = downstream(apiName, change.endpoint(), change.field(), change.jsonPointer());
            List<UpstreamRef> up = change.field() == null
                    ? List.of()
                    : upstreamOf(apiName, change.endpoint(), change.field());
            impacts.add(new Impact(change, down, up));
        }
        return impacts;
    }

    public List<ConsumerImpact> downstreamOf(String api, String endpoint, String field) {
        return downstream(api, endpoint, field, null);
    }

    private List<ConsumerImpact> downstream(String api, String endpoint, String field, String pointer) {
        List<ConsumerImpact> hits = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (Edge edge : edges) {
            if (!equalsIgnoreCase(edge.api, api) || !endpointMatches(endpoint, edge.endpoint)) {
                continue;
            }
            boolean fieldMatch = field == null
                    || edge.fields.isEmpty()
                    || edge.fields.contains(field)
                    || (pointer != null && edge.fields.stream().anyMatch(f -> pointerMentions(pointer, f)));
            if (fieldMatch && seen.add(edge.consumer.consumer())) {
                hits.add(edge.consumer.withMatchedField(field == null ? "*" : field));
            }
        }
        return hits;
    }

    public List<UpstreamRef> upstreamOf(String api, String endpoint, String field) {
        List<UpstreamRef> hits = new ArrayList<>();
        for (int i = 0; i < upstream.size(); i++) {
            FieldSourceManifest.Source s = upstream.get(i);
            if (equalsIgnoreCase(upstreamApis.get(i), api)
                    && endpointMatches(endpoint, s.endpoint)
                    && equalsIgnoreCase(s.field, field)
                    && s.from != null) {
                hits.add(new UpstreamRef(s.from.api, s.from.endpoint, s.from.field));
            }
        }
        return hits;
    }

    public static boolean endpointMatches(String changeEndpoint, String manifestPath) {
        if (changeEndpoint == null || manifestPath == null) {
            return false;
        }

        if (manifestPath.equals("*") || manifestPath.equals("* *")) {
            return true;
        }
        String[] a = split(changeEndpoint);
        String[] b = split(manifestPath);
        if (!a[1].equals(b[1])) {
            return false;
        }
        return a[0] == null || b[0] == null || a[0].equalsIgnoreCase(b[0]);
    }

    private static String[] split(String endpoint) {
        String s = endpoint.strip();
        int sp = s.indexOf(' ');
        if (sp < 0) {
            return new String[]{null, s};
        }
        return new String[]{s.substring(0, sp), s.substring(sp + 1).strip()};
    }

    private static boolean pointerMentions(String pointer, String field) {
        return pointer.equals(field)
                || pointer.endsWith("." + field)
                || pointer.contains("." + field + ".")
                || pointer.contains("." + field + "[");
    }

    private static boolean equalsIgnoreCase(String a, String b) {
        return a != null && a.equalsIgnoreCase(b);
    }

    private static <T> List<T> nullSafe(List<T> list) {
        return list == null ? List.of() : list;
    }

    public record ConsumerImpact(String consumer, String ownerTeam, List<String> reviewers,
                                 String slackChannel, String sourceRepo, String matchedField) {
        ConsumerImpact withMatchedField(String field) {
            return new ConsumerImpact(consumer, ownerTeam, reviewers, slackChannel, sourceRepo, field);
        }
    }

    public record UpstreamRef(String api, String endpoint, String field) {
    }

    public record Impact(Change change, List<ConsumerImpact> downstream, List<UpstreamRef> upstream) {
        public boolean hasImpact() {
            return !downstream.isEmpty() || !upstream.isEmpty();
        }
    }
}
