package com.apiguard.server.service;

import com.apiguard.core.mule.MuleProjectScanner;
import com.apiguard.core.mule.MuleScan;
import com.apiguard.server.web.Dtos;
import org.springframework.stereotype.Service;

import java.nio.file.Files;
import java.util.List;

@Service
public class ScanService {

    private final ManifestService manifestService;
    private final RepoFetchService repoFetch;

    public ScanService(ManifestService manifestService, RepoFetchService repoFetch) {
        this.manifestService = manifestService;
        this.repoFetch = repoFetch;
    }

    public Dtos.ScanResultDto scan(String pathOrUrl) {
        return ingest(fetchAndScan(pathOrUrl));
    }

    public List<MuleScan> fetchAndScan(String pathOrUrl) {
        RepoFetchService.Fetched fetched = repoFetch.fetch(pathOrUrl.trim());
        try {
            if (!Files.exists(fetched.dir())) {
                throw new IllegalArgumentException("Path not found on server: " + pathOrUrl);
            }
            return MuleProjectScanner.scanAll(fetched.dir());
        } finally {
            repoFetch.cleanup(fetched);
        }
    }

    public Dtos.ScanResultDto ingest(List<MuleScan> scans) {
        List<Dtos.MuleScanDto> dtos = scans.stream().map(scan -> {
            manifestService.ingestDependency(scan.toManifest());
            List<Dtos.MuleEndpointDto> endpoints = scan.endpoints().stream()
                    .map(ep -> new Dtos.MuleEndpointDto(ep.label(),
                            ep.calls().stream()
                                    .map(c -> new Dtos.MuleCallDto(c.api(), c.endpoint()))
                                    .toList()))
                    .toList();
            List<Dtos.ConfigDriftDto> drift = scan.configDrift().stream()
                    .map(w -> new Dtos.ConfigDriftDto(w.configName(), w.host(), w.unresolvedPlaceholder()))
                    .toList();
            return new Dtos.MuleScanDto(scan.app(), scan.groupId(), scan.version(),
                    scan.downstreamApis(), endpoints,
                    scan.declaredApis(), scan.undeclaredCalls(), drift);
        }).toList();
        return new Dtos.ScanResultDto(dtos.size(), dtos);
    }
}
