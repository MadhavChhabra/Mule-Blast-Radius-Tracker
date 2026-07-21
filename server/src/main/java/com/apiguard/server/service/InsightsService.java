package com.apiguard.server.service;

import com.apiguard.core.catalog.ApiLayer;
import com.apiguard.core.catalog.EstateInsights;
import com.apiguard.server.web.Dtos;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class InsightsService {

    private final GraphService graph;

    public InsightsService(GraphService graph) {
        this.graph = graph;
    }

    public List<EstateInsights.Finding> compute() {
        return computeFor(graph.build());
    }

    public List<EstateInsights.Finding> computeFor(Dtos.GraphDto g) {
        List<EstateInsights.Node> nodes = g.nodes().stream()
                .map(n -> new EstateInsights.Node(n.id(), parseLayer(n.layer())))
                .toList();
        List<EstateInsights.Edge> edges = g.edges().stream()
                .map(e -> new EstateInsights.Edge(e.from(), e.to()))
                .toList();
        return EstateInsights.analyze(nodes, edges);
    }

    private static ApiLayer parseLayer(String layer) {
        try {
            return layer == null ? ApiLayer.UNKNOWN : ApiLayer.valueOf(layer);
        } catch (IllegalArgumentException e) {
            return ApiLayer.UNKNOWN;
        }
    }
}
