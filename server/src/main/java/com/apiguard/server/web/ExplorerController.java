package com.apiguard.server.web;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.server.service.ManifestService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ExplorerController {

    private final ManifestService manifestService;

    public ExplorerController(ManifestService manifestService) {
        this.manifestService = manifestService;
    }

    @GetMapping("/api/explorer")
    public Dtos.ExplorerResponse explore(@RequestParam String api,
                                         @RequestParam String endpoint,
                                         @RequestParam(required = false) String field) {
        BlastRadiusResolver resolver = manifestService.buildResolver();
        var downstream = resolver.downstreamOf(api, endpoint, field).stream()
                .map(Dtos.ConsumerDto::from).toList();
        var upstream = field == null ? java.util.List.<Dtos.UpstreamDto>of()
                : resolver.upstreamOf(api, endpoint, field).stream().map(Dtos.UpstreamDto::from).toList();
        return new Dtos.ExplorerResponse(api, endpoint, field, downstream, upstream);
    }
}
