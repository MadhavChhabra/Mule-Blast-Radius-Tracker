package com.apiguard.server.web;

import com.apiguard.server.service.ScanService;
import jakarta.validation.constraints.NotBlank;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ScanController {

    private final ScanService scanService;

    public ScanController(ScanService scanService) {
        this.scanService = scanService;
    }

    public record ScanRequest(@NotBlank String path) {
    }

    @PostMapping("/api/scan")
    public Dtos.ScanResultDto scan(@RequestBody ScanRequest req) {
        return scanService.scan(req.path());
    }
}
