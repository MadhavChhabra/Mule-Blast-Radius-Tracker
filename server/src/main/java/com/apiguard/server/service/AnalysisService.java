package com.apiguard.server.service;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.blast.RiskScorer;
import com.apiguard.core.changelog.ChangelogGenerator;
import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.Classification;
import com.apiguard.core.diff.DiffEngine;
import com.apiguard.core.diff.VersionAdvisor;
import com.apiguard.core.spec.SpecLoader;
import com.apiguard.server.domain.ApiEntity;
import com.apiguard.server.domain.ChangeRecordEntity;
import com.apiguard.server.domain.ChangelogEntryEntity;
import com.apiguard.server.domain.DependencyManifestEntity;
import com.apiguard.server.domain.SpecVersionEntity;
import com.apiguard.server.repo.ApiRepository;
import com.apiguard.server.repo.ChangeRepository;
import com.apiguard.server.repo.ChangelogRepository;
import com.apiguard.server.repo.SpecVersionRepository;
import com.apiguard.server.web.Dtos;
import io.swagger.v3.oas.models.OpenAPI;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

@Service
public class AnalysisService {

    private final ApiRepository apis;
    private final SpecVersionRepository specVersions;
    private final ChangeRepository changes;
    private final ChangelogRepository changelogs;
    private final ManifestService manifestService;
    private final NotificationService notificationService;

    private final DiffEngine diffEngine = new DiffEngine();
    private final ChangelogGenerator changelogGenerator = new ChangelogGenerator();

    public AnalysisService(ApiRepository apis, SpecVersionRepository specVersions, ChangeRepository changes,
                           ChangelogRepository changelogs, ManifestService manifestService,
                           NotificationService notificationService) {
        this.apis = apis;
        this.specVersions = specVersions;
        this.changes = changes;
        this.changelogs = changelogs;
        this.manifestService = manifestService;
        this.notificationService = notificationService;
    }

    public record AnalyzeCommand(String apiName, String repo, String oldSpec, String newSpec,
                                 String fromLabel, String toLabel, String prRef, boolean notifyPr) {
    }

    @Transactional
    public Dtos.AnalyzeResponse analyze(AnalyzeCommand cmd) {
        OpenAPI oldApi = SpecLoader.loadString(cmd.oldSpec());
        OpenAPI newApi = SpecLoader.loadString(cmd.newSpec());

        List<Change> diff = diffEngine.diff(oldApi, newApi).stream()
                .sorted(Comparator.comparing((Change c) -> c.classification().ordinal())
                        .thenComparing(c -> c.endpoint() == null ? "" : c.endpoint()))
                .toList();

        ApiEntity api = apis.findByName(cmd.apiName())
                .orElseGet(() -> apis.save(new ApiEntity(cmd.apiName(), cmd.repo(), null)));
        SpecVersionEntity from = specVersions.save(new SpecVersionEntity(api, null, cmd.fromLabel(), cmd.oldSpec()));
        SpecVersionEntity to = specVersions.save(new SpecVersionEntity(api, null, cmd.toLabel(), cmd.newSpec()));
        for (Change c : diff) {
            changes.save(new ChangeRecordEntity(api, from, to, c));
        }
        String changelogMd = changelogGenerator.generate(diff, cmd.toLabel());
        changelogs.save(new ChangelogEntryEntity(api, to, cmd.toLabel(), changelogMd));

        BlastRadiusResolver resolver = manifestService.buildResolver();
        List<BlastRadiusResolver.Impact> impacts = resolver.resolve(cmd.apiName(), diff);

        Map<String, DependencyManifestEntity> byConsumer = new LinkedHashMap<>();
        for (DependencyManifestEntity m : manifestService.all()) {
            if (m.getConsumer() != null) {
                byConsumer.put(m.getConsumer().toLowerCase(Locale.ROOT), m);
            }
        }

        long impactedConsumers = impacts.stream()
                .filter(i -> i.change().isBreaking())
                .flatMap(i -> i.downstream().stream())
                .map(BlastRadiusResolver.ConsumerImpact::consumer)
                .distinct().count();

        long breaking = diff.stream().filter(Change::isBreaking).count();
        long additive = diff.stream().filter(c -> c.classification() == Classification.ADDITIVE).count();
        VersionAdvisor.Bump bump = VersionAdvisor.recommend(diff);
        String currentVersion = newApi.getInfo() != null ? newApi.getInfo().getVersion() : null;
        String nextVersion = VersionAdvisor.nextVersion(currentVersion, bump);
        RiskScorer.Risk risk = RiskScorer.score((int) breaking, (int) additive, (int) impactedConsumers);
        Dtos.AdvisoryDto advisory = new Dtos.AdvisoryDto(
                bump.name(), currentVersion, nextVersion, risk.score(), risk.level().name());

        if (cmd.notifyPr() && cmd.prRef() != null) {
            String versionAdvice = bump.name()
                    + (currentVersion != null && nextVersion != null ? " (" + currentVersion + " → " + nextVersion + ")" : "");
            notificationService.notifyImpacts(cmd.apiName(), cmd.repo(), cmd.prRef(), impacts, changelogMd, versionAdvice);
        }

        return new Dtos.AnalyzeResponse(
                cmd.apiName(),
                Dtos.SummaryDto.from(diff, impactedConsumers),
                advisory,
                impacts.stream().map(i -> enrichImpact(i, byConsumer)).toList(),
                changelogMd);
    }

    private static Dtos.ImpactDto enrichImpact(BlastRadiusResolver.Impact i,
                                               Map<String, DependencyManifestEntity> byConsumer) {
        List<Dtos.ConsumerDto> downstream = i.downstream().stream()
                .map(c -> {
                    DependencyManifestEntity m = c.consumer() == null
                            ? null
                            : byConsumer.get(c.consumer().toLowerCase(Locale.ROOT));
                    String lastSeen = m == null || m.getUpdatedAt() == null ? null : m.getUpdatedAt().toString();
                    boolean discovered = m != null
                            && (m.getReviewers() == null || m.getReviewers().isEmpty());
                    return Dtos.ConsumerDto.from(c, lastSeen, discovered);
                })
                .toList();
        List<Dtos.UpstreamDto> upstream = i.upstream().stream().map(Dtos.UpstreamDto::from).toList();
        return new Dtos.ImpactDto(Dtos.ChangeDto.from(i.change()), downstream, upstream);
    }
}
