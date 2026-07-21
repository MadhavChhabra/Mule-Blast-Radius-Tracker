package com.apiguard.server.web;

import com.apiguard.server.service.ReportService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ReportController {

    private final ReportService report;

    public ReportController(ReportService report) {
        this.report = report;
    }

    @GetMapping(value = "/api/report", produces = "text/markdown;charset=UTF-8")
    public ResponseEntity<String> estateReport(
            @RequestParam(name = "download", defaultValue = "false") boolean download) {
        ResponseEntity.BodyBuilder builder = ResponseEntity.ok()
                .contentType(MediaType.parseMediaType("text/markdown;charset=UTF-8"));
        if (download) {
            builder.header(HttpHeaders.CONTENT_DISPOSITION,
                    "attachment; filename=\"wakegraph-estate-report.md\"");
        }
        return builder.body(report.markdown());
    }
}
