package com.apiguard.server.web;

import com.apiguard.server.service.SpecArchiveService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;

@RestController
public class SpecController {

    private final SpecArchiveService archive;

    public SpecController(SpecArchiveService archive) {
        this.archive = archive;
    }

    public record ExtractedSpecDto(String title, String version, String spec) {
    }

    @PostMapping("/api/spec/from-zip")
    public ExtractedSpecDto fromZip(@RequestParam("file") MultipartFile file) throws IOException {
        if (file.isEmpty()) {
            throw new IllegalArgumentException("No file uploaded.");
        }
        SpecArchiveService.ExtractedSpec extracted = archive.fromZip(file.getInputStream());
        return new ExtractedSpecDto(extracted.title(), extracted.version(), extracted.spec());
    }
}
