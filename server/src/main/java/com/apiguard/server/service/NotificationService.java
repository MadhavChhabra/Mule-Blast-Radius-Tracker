package com.apiguard.server.service;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.blast.RiskScorer;
import com.apiguard.server.domain.BlastResultEntity;
import com.apiguard.server.notify.GitHubClient;
import com.apiguard.server.notify.SlackNotifier;
import com.apiguard.server.repo.BlastResultRepository;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

@Service
public class NotificationService {

    private final SlackNotifier slack;
    private final GitHubClient github;
    private final BlastResultRepository blastResults;

    public NotificationService(SlackNotifier slack, GitHubClient github, BlastResultRepository blastResults) {
        this.slack = slack;
        this.github = github;
        this.blastResults = blastResults;
    }

    public void notifyImpacts(String apiName, String repo, String prRef,
                              List<BlastRadiusResolver.Impact> impacts, String changelogMd) {
        notifyImpacts(apiName, repo, prRef, impacts, changelogMd, null);
    }

    public void notifyImpacts(String apiName, String repo, String prRef,
                              List<BlastRadiusResolver.Impact> impacts, String changelogMd, String versionAdvice) {
        int prNumber = parsePrNumber(prRef);

        Set<String> reviewers = new LinkedHashSet<>();
        Set<String> slackChannels = new LinkedHashSet<>();
        for (BlastRadiusResolver.Impact impact : impacts) {
            if (!impact.change().isBreaking()) {
                continue;
            }
            for (BlastRadiusResolver.ConsumerImpact c : impact.downstream()) {
                c.reviewers().forEach(r -> reviewers.add(r.replaceFirst("^gh:", "")));
                if (c.slackChannel() != null) {
                    slackChannels.add(c.slackChannel());
                }
                if (repo != null && prNumber > 0) {
                    blastResults.save(new BlastResultEntity(prRef, null, c.consumer(), Instant.now()));
                }
            }
        }

        if (repo != null && prNumber > 0) {
            github.requestReviewers(repo, prNumber, List.copyOf(reviewers));
            github.comment(repo, prNumber, buildComment(impacts, changelogMd, versionAdvice));
        }

        if (!slackChannels.isEmpty() || slack.isEnabled()) {
            slack.post(buildSlackMessage(apiName, prRef, impacts, slackChannels));
        }
    }

    private String buildComment(List<BlastRadiusResolver.Impact> impacts, String changelogMd, String versionAdvice) {
        long breaking = impacts.stream().filter(i -> i.change().isBreaking()).count();
        long additive = impacts.stream().filter(i -> i.change().classification().name().equals("ADDITIVE")).count();
        long impactedConsumers = impacts.stream()
                .filter(i -> i.change().isBreaking())
                .flatMap(i -> i.downstream().stream())
                .map(BlastRadiusResolver.ConsumerImpact::consumer).distinct().count();
        RiskScorer.Risk risk = RiskScorer.score((int) breaking, (int) additive, (int) impactedConsumers);

        StringBuilder sb = new StringBuilder("## 🛡️ Wakegraph report\n\n");

        sb.append("| Deployment risk | Recommended version |\n|---|---|\n");
        sb.append("| ").append(riskBadge(risk)).append(" | ")
                .append(versionAdvice == null ? "—" : versionAdvice).append(" |\n\n");
        sb.append(breaking == 0 ? "No breaking changes detected.\n\n"
                : "**" + breaking + " breaking change(s)** detected.\n\n");
        for (BlastRadiusResolver.Impact i : impacts) {
            if (!i.change().isBreaking()) {
                continue;
            }
            sb.append("- **`").append(i.change().endpoint()).append("`** ")
                    .append(i.change().description());
            if (!i.downstream().isEmpty()) {
                sb.append(" — impacts ");
                sb.append(String.join(", ", i.downstream().stream()
                        .map(BlastRadiusResolver.ConsumerImpact::consumer).toList()));
            }
            sb.append('\n');
        }
        sb.append("\n<details><summary>Changelog</summary>\n\n").append(changelogMd).append("\n</details>\n");
        return sb.toString();
    }

    private String buildSlackMessage(String apiName, String prRef,
                                     List<BlastRadiusResolver.Impact> impacts, Set<String> channels) {
        long breaking = impacts.stream().filter(i -> i.change().isBreaking()).count();
        Set<String> consumers = new LinkedHashSet<>();
        impacts.stream().filter(i -> i.change().isBreaking())
                .flatMap(i -> i.downstream().stream())
                .forEach(c -> consumers.add(c.consumer()));
        return ":shield: *Wakegraph* — `" + apiName + "` PR " + prRef + "\n"
                + breaking + " breaking change(s)"
                + (consumers.isEmpty() ? "" : " affecting: " + String.join(", ", consumers))
                + (channels.isEmpty() ? "" : "\ncc " + String.join(" ", channels));
    }

    private static String riskBadge(RiskScorer.Risk risk) {
        String emoji = switch (risk.level()) {
            case CRITICAL -> "🔴";
            case HIGH -> "🟠";
            case MEDIUM -> "🟡";
            case LOW -> "🟢";
            case NONE -> "⚪";
        };
        return emoji + " **" + risk.level() + "** (" + risk.score() + "/100)";
    }

    private static int parsePrNumber(String prRef) {
        if (prRef == null) {
            return -1;
        }
        String digits = prRef.replaceAll("\\D+", "");
        return digits.isEmpty() ? -1 : Integer.parseInt(digits);
    }
}
