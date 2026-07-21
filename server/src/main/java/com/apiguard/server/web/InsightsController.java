package com.apiguard.server.web;

import com.apiguard.core.catalog.EstateInsights;
import com.apiguard.server.service.InsightsService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
public class InsightsController {

    private final InsightsService insights;

    public InsightsController(InsightsService insights) {
        this.insights = insights;
    }

    @GetMapping("/api/insights")
    public List<EstateInsights.Finding> insights() {
        return insights.compute();
    }
}
