package com.apiguard.server.web;

import com.apiguard.server.service.ManifestService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;

@RestController
public class CatalogController {

    private final ManifestService manifestService;

    public CatalogController(ManifestService manifestService) {
        this.manifestService = manifestService;
    }

    public record EndpointSurface(String path, List<String> fields) {
    }

    public record ApiSurface(String api, List<EndpointSurface> endpoints) {
    }

    @GetMapping("/api/catalog")
    public ApiSurface catalog(@RequestParam String api) {
        List<EndpointSurface> endpoints = new ArrayList<>();
        manifestService.apiSurface(api).forEach((path, fields) ->
                endpoints.add(new EndpointSurface(path, new ArrayList<>(fields))));
        return new ApiSurface(api, endpoints);
    }
}
