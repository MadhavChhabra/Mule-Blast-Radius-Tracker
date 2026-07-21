package com.apiguard.core.catalog;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Deque;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public final class EstateInsights {

    public record Node(String name, ApiLayer layer) {
    }

    public record Edge(String from, String to) {
    }

    public record Finding(String rule, String severity, String title, String detail, List<String> apis) {
    }

    public static final int FAN_IN_THRESHOLD = 4;

    private EstateInsights() {
    }

    public static List<Finding> analyze(List<Node> nodes, List<Edge> edges) {
        Map<String, ApiLayer> layers = new LinkedHashMap<>();
        for (Node n : nodes) {
            layers.put(n.name(), n.layer());
        }
        List<Finding> findings = new ArrayList<>();
        layerViolations(edges, layers, findings);
        cycles(edges, findings);
        fanInHotspots(edges, layers, findings);
        findings.sort(Comparator.comparingInt(f -> severityRank(f.severity())));
        return findings;
    }

    private static int rank(ApiLayer layer) {
        return switch (layer) {
            case APP -> 0;
            case EXPERIENCE -> 1;
            case PROCESS -> 2;
            case SYSTEM -> 3;
            case BACKEND -> 4;
            case UNKNOWN -> -1;
        };
    }

    private static void layerViolations(List<Edge> edges, Map<String, ApiLayer> layers, List<Finding> findings) {
        for (Edge e : edges) {
            ApiLayer from = layers.getOrDefault(e.from(), ApiLayer.UNKNOWN);
            ApiLayer to = layers.getOrDefault(e.to(), ApiLayer.UNKNOWN);
            int rFrom = rank(from);
            int rTo = rank(to);
            if (rFrom < 0 || rTo < 0 || e.from().equals(e.to())) {
                continue;
            }
            if (rFrom > rTo) {
                findings.add(new Finding("upward-call", "high",
                        "Upward call: " + e.from() + " → " + e.to(),
                        from.label() + " \"" + e.from() + "\" calls " + article(to.label()) + " above it. "
                                + "Lower layers must not know about upper layers — this inverts API-led "
                                + "direction and makes the estate impossible to change safely.",
                        List.of(e.from(), e.to())));
            } else if (rTo - rFrom >= 2 && !(from == ApiLayer.PROCESS && to == ApiLayer.BACKEND)) {
                findings.add(new Finding("layer-skip", "medium",
                        "Layer skip: " + e.from() + " → " + e.to(),
                        from.label() + " \"" + e.from() + "\" reaches " + article(to.label())
                                + " directly, skipping the layer(s) between. The skipped layer is where "
                                + "reuse, throttling and access control live.",
                        List.of(e.from(), e.to())));
            } else if (from == ApiLayer.PROCESS && to == ApiLayer.BACKEND) {
                findings.add(new Finding("layer-skip", "info",
                        "Process API touches a system of record: " + e.from() + " → " + e.to(),
                        "\"" + e.from() + "\" integrates \"" + e.to() + "\" directly. Consider a System API "
                                + "in front of it so other processes can reuse the connection.",
                        List.of(e.from(), e.to())));
            }
        }
    }

    private static String article(String label) {
        String l = label.toLowerCase();
        return (l.startsWith("a") || l.startsWith("e") || l.startsWith("i") || l.startsWith("o") || l.startsWith("u")
                ? "an " : "a ") + label;
    }

    private static void cycles(List<Edge> edges, List<Finding> findings) {
        Map<String, List<String>> adj = new LinkedHashMap<>();
        Set<String> selfLoops = new HashSet<>();
        for (Edge e : edges) {
            adj.computeIfAbsent(e.from(), k -> new ArrayList<>()).add(e.to());
            adj.computeIfAbsent(e.to(), k -> new ArrayList<>());
            if (e.from().equals(e.to())) {
                selfLoops.add(e.from());
            }
        }
        for (List<String> scc : stronglyConnected(adj)) {
            boolean cycle = scc.size() > 1 || (scc.size() == 1 && selfLoops.contains(scc.get(0)));
            if (!cycle) {
                continue;
            }
            findings.add(new Finding("dependency-cycle", "high",
                    "Dependency cycle: " + String.join(" → ", scc) + " → " + scc.get(0),
                    "These APIs depend on each other in a loop, so none can be versioned, deployed or "
                            + "retired independently — every change's blast radius includes the whole cycle.",
                    List.copyOf(scc)));
        }
    }

    private static List<List<String>> stronglyConnected(Map<String, List<String>> adj) {
        Map<String, Integer> index = new HashMap<>();
        Map<String, Integer> low = new HashMap<>();
        Set<String> onStack = new HashSet<>();
        Deque<String> stack = new ArrayDeque<>();
        List<List<String>> sccs = new ArrayList<>();
        int[] counter = {0};

        for (String start : adj.keySet()) {
            if (index.containsKey(start)) {
                continue;
            }

            Deque<String> nodeFrames = new ArrayDeque<>();
            Deque<Integer> posFrames = new ArrayDeque<>();
            nodeFrames.push(start);
            posFrames.push(0);
            index.put(start, counter[0]);
            low.put(start, counter[0]);
            counter[0]++;
            stack.push(start);
            onStack.add(start);

            while (!nodeFrames.isEmpty()) {
                String v = nodeFrames.peek();
                int pos = posFrames.pop();
                List<String> children = adj.getOrDefault(v, List.of());
                if (pos < children.size()) {
                    posFrames.push(pos + 1);
                    String w = children.get(pos);
                    if (!index.containsKey(w)) {
                        nodeFrames.push(w);
                        posFrames.push(0);
                        index.put(w, counter[0]);
                        low.put(w, counter[0]);
                        counter[0]++;
                        stack.push(w);
                        onStack.add(w);
                    } else if (onStack.contains(w)) {
                        low.merge(v, index.get(w), Math::min);
                    }
                } else {
                    nodeFrames.pop();
                    if (!nodeFrames.isEmpty()) {
                        low.merge(nodeFrames.peek(), low.get(v), Math::min);
                    }
                    if (low.get(v).equals(index.get(v))) {
                        List<String> scc = new ArrayList<>();
                        String w;
                        do {
                            w = stack.pop();
                            onStack.remove(w);
                            scc.add(w);
                        } while (!w.equals(v));
                        sccs.add(scc);
                    }
                }
            }
        }
        return sccs;
    }

    private static void fanInHotspots(List<Edge> edges, Map<String, ApiLayer> layers, List<Finding> findings) {
        Map<String, Set<String>> consumersOf = new LinkedHashMap<>();
        for (Edge e : edges) {
            if (!e.from().equals(e.to())) {
                consumersOf.computeIfAbsent(e.to(), k -> new HashSet<>()).add(e.from());
            }
        }
        consumersOf.forEach((api, consumers) -> {
            if (consumers.size() >= FAN_IN_THRESHOLD) {
                List<String> involved = new ArrayList<>();
                involved.add(api);
                involved.addAll(consumers.stream().sorted().toList());
                findings.add(new Finding("change-hotspot", "info",
                        "Change hotspot: " + consumers.size() + " consumers depend on " + api,
                        "A breaking change in \"" + api + "\" propagates to " + consumers.size()
                                + " consumers at once. Treat its contract as frozen: additive changes only, "
                                + "and version deliberately.",
                        List.copyOf(involved)));
            }
        });
    }

    private static int severityRank(String severity) {
        return switch (severity) {
            case "high" -> 0;
            case "medium" -> 1;
            default -> 2;
        };
    }
}
