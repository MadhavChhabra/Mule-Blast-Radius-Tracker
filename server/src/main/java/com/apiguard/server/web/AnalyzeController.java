package com.apiguard.server.web;

import com.apiguard.server.service.AnalysisService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/analyze")
public class AnalyzeController {

    private final AnalysisService analysisService;

    public AnalyzeController(AnalysisService analysisService) {
        this.analysisService = analysisService;
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
        return analysisService.analyze(new AnalysisService.AnalyzeCommand(
                req.api(), req.repo(), req.oldSpec(), req.newSpec(),
                req.fromLabel(), req.toLabel(), req.prRef(), req.notifyPr()));
    }
}
