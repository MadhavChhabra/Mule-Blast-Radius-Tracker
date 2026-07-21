package com.apiguard.server.web;

import com.apiguard.server.service.AnalysisService;
import com.apiguard.server.service.AuditService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/analyze")
public class AnalyzeController {

    private final AnalysisService analysisService;
    private final AuditService audit;

    public AnalyzeController(AnalysisService analysisService, AuditService audit) {
        this.analysisService = analysisService;
        this.audit = audit;
    }

    public record AnalyzeRequest(
            @NotBlank String api,
            String repo,
            @NotBlank String oldSpec,
            @NotBlank String newSpec,
            String fromLabel,
            String toLabel,
            String prRef,
            boolean notifyPr) {
    }

    @PostMapping
    public Dtos.AnalyzeResponse analyze(@RequestBody AnalyzeRequest req) {
        Dtos.AnalyzeResponse response = analysisService.analyze(new AnalysisService.AnalyzeCommand(
                req.api(), req.repo(), req.oldSpec(), req.newSpec(),
                req.fromLabel(), req.toLabel(), req.prRef(), req.notifyPr()));
        audit.record("analyze", req.api(),
                "changes=" + response.summary().total()
                        + " breaking=" + response.summary().breaking()
                        + " impacted=" + response.summary().impactedConsumers()
                        + (req.prRef() == null ? "" : " pr=" + req.prRef()));
        return response;
    }
}
