package com.apiguard.cli;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.Classification;
import com.apiguard.core.diff.Remediation;

import java.util.List;

final class CliOutput {

    private CliOutput() {
    }

    static void printChanges(Ansi ansi, List<Change> changes) {
        if (changes.isEmpty()) {
            System.out.println(ansi.green("No API changes detected."));
            return;
        }
        for (Change c : changes) {
            System.out.println(line(ansi, c));
            printRemediation(ansi, c);
        }
        printSummary(ansi, changes);
    }

    static void printImpacts(Ansi ansi, List<BlastRadiusResolver.Impact> impacts) {
        if (impacts.isEmpty()) {
            System.out.println(ansi.green("No API changes detected."));
            return;
        }
        for (BlastRadiusResolver.Impact impact : impacts) {
            System.out.println(line(ansi, impact.change()));
            printRemediation(ansi, impact.change());

            List<BlastRadiusResolver.ConsumerImpact> down = impact.downstream();
            boolean breaking = impact.change().isBreaking();
            if (down.isEmpty()) {
                System.out.println("  " + ansi.dim("down  no consumers affected"));
            } else {
                String verb = breaking
                        ? (down.size() == 1 ? " consumer may break:" : " consumers may break:")
                        : (down.size() == 1 ? " consumer depends on this (safe):" : " consumers depend on this (safe):");
                System.out.println("  " + ansi.bold("down") + "  " + down.size() + verb);
                for (var c : down) {
                    String reviewers = String.join(",", c.reviewers()).replace("gh:", "");
                    System.out.println("      - " + String.format("%-18s", c.consumer())
                            + ansi.dim("team=" + nvl(c.ownerTeam()) + "   reviewers=" + reviewers
                            + (c.slackChannel() != null ? "   slack=" + c.slackChannel() : "")));
                }
            }

            List<BlastRadiusResolver.UpstreamRef> up = impact.upstream();
            if (!up.isEmpty()) {
                System.out.println("  " + ansi.bold("up") + "    sourced from:");
                for (var u : up) {
                    System.out.println("      - " + u.api() + "  " + u.endpoint() + "." + u.field());
                }
            }
        }
        printSummary(ansi, impacts.stream().map(BlastRadiusResolver.Impact::change).toList());
    }

    private static String line(Ansi ansi, Change c) {
        StringBuilder sb = new StringBuilder();
        sb.append(ansi.classification(c.classification())).append("  ");
        if (c.endpoint() != null) {
            sb.append(ansi.cyan(c.endpoint())).append("  ");
        }
        if (c.jsonPointer() != null && !c.jsonPointer().equals(c.endpoint())) {
            sb.append(c.jsonPointer()).append("  ");
        }
        sb.append(ansi.dim("(" + (c.description() != null ? c.description() : c.kind().label()) + ")"));
        return sb.toString();
    }

    private static void printRemediation(Ansi ansi, Change c) {
        String hint = Remediation.forChange(c);
        if (hint != null) {
            System.out.println("  " + ansi.dim("→ ship it safely: " + hint));
        }
    }

    private static void printSummary(Ansi ansi, List<Change> changes) {
        long breaking = changes.stream().filter(Change::isBreaking).count();
        long additive = changes.stream().filter(c -> c.classification() == Classification.ADDITIVE).count();
        long safe = changes.size() - breaking - additive;
        System.out.println();
        String summary = breaking + " breaking, " + safe + " safe, " + additive + " additive";
        System.out.println(breaking > 0 ? ansi.red(ansi.bold(summary)) : ansi.green(summary));
    }

    private static String nvl(String s) {
        return s == null ? "?" : s;
    }
}
