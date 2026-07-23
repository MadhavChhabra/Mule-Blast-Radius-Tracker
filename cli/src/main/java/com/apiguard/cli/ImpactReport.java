package com.apiguard.cli;

import com.fasterxml.jackson.databind.JsonNode;

final class ImpactReport {

    private ImpactReport() {
    }

    enum FailOn { BREAKING_IMPACT, BREAKING, NEVER }

    static int exitCode(JsonNode response, FailOn failOn) {
        long breaking = response.path("summary").path("breaking").asLong(0);
        long impacted = response.path("summary").path("impactedConsumers").asLong(0);
        return switch (failOn) {
            case BREAKING_IMPACT -> breaking > 0 && impacted > 0 ? 1 : 0;
            case BREAKING -> breaking > 0 ? 1 : 0;
            case NEVER -> 0;
        };
    }

    static void renderConsole(JsonNode r, Ansi ansi, java.io.PrintStream out) {
        JsonNode s = r.path("summary");
        JsonNode a = r.path("advisory");
        out.println(ansi.bold("Wakegraph impact — " + r.path("api").asText("?")));
        out.println(ansi.dim(s.path("total").asInt() + " change(s): "
                + s.path("breaking").asLong() + " breaking · "
                + s.path("safe").asLong() + " non-breaking · "
                + s.path("additive").asLong() + " additive"));
        String riskLine = "Deployment risk: " + a.path("riskLevel").asText("?")
                + " (" + a.path("riskScore").asInt() + "/100)   Recommended bump: "
                + a.path("recommendedBump").asText("?");
        String level = a.path("riskLevel").asText("");
        out.println(level.equals("CRITICAL") || level.equals("HIGH")
                ? ansi.red(ansi.bold(riskLine)) : ansi.yellow(riskLine));
        out.println();

        for (JsonNode impact : r.path("impacts")) {
            JsonNode c = impact.path("change");
            boolean isBreaking = "BREAKING".equals(c.path("classification").asText());
            if (!isBreaking && impact.path("downstream").isEmpty()) {
                continue;
            }
            String head = (c.path("endpoint").isMissingNode() || c.path("endpoint").isNull()
                    ? "" : c.path("endpoint").asText() + "  ")
                    + c.path("description").asText();
            out.println(isBreaking ? ansi.red("✖ " + head) : ansi.yellow("• " + head));
            String remediation = c.path("remediation").asText("");
            if (isBreaking && !remediation.isEmpty()) {
                out.println(ansi.dim("    → ship it safely: " + remediation));
            }
            String verb = isBreaking ? "breaks " : "reaches ";
            for (JsonNode d : impact.path("downstream")) {
                String readiness = readinessSuffix(d);
                out.println(ansi.dim("    ↳ " + verb + d.path("consumer").asText()
                        + teamSuffix(d)
                        + (readiness.isEmpty() ? "" : "   " + readiness.replace("_", ""))));
            }
        }
        long impacted = s.path("impactedConsumers").asLong();
        out.println();
        if (s.path("breaking").asLong() == 0) {
            out.println(ansi.green("No breaking changes."));
        } else if (impacted == 0) {
            out.println(ansi.yellow(s.path("breaking").asLong()
                    + " breaking change(s), but no known consumer is impacted."));
        } else {
            out.println(ansi.red(ansi.bold(s.path("breaking").asLong() + " breaking change(s) hit "
                    + impacted + " consumer(s) in the estate.")));
        }
    }

    static String renderMarkdown(JsonNode r) {
        JsonNode s = r.path("summary");
        JsonNode a = r.path("advisory");
        StringBuilder md = new StringBuilder();
        md.append("## 🛡️ Wakegraph impact — `").append(r.path("api").asText("?")).append("`\n\n");

        String riskEmoji = switch (a.path("riskLevel").asText("")) {
            case "CRITICAL" -> "🟥";
            case "HIGH" -> "🟧";
            case "MEDIUM" -> "🟨";
            default -> "🟩";
        };
        md.append(riskEmoji).append(" **Deployment risk: ").append(a.path("riskLevel").asText("?"))
                .append(" (").append(a.path("riskScore").asInt()).append("/100)**");
        md.append(" · recommended bump: **").append(a.path("recommendedBump").asText("?")).append("**");
        if (!a.path("nextVersion").asText("").isEmpty()) {
            md.append(" (").append(a.path("currentVersion").asText("?")).append(" → ")
                    .append(a.path("nextVersion").asText()).append(")");
        }
        md.append("\n\n");

        md.append("| Changes | Breaking | Non-breaking | Additive | Impacted consumers |\n");
        md.append("|---:|---:|---:|---:|---:|\n");
        md.append("| ").append(s.path("total").asInt())
                .append(" | ").append(s.path("breaking").asLong())
                .append(" | ").append(s.path("safe").asLong())
                .append(" | ").append(s.path("additive").asLong())
                .append(" | ").append(s.path("impactedConsumers").asLong()).append(" |\n\n");

        boolean anyBreaking = false;
        StringBuilder breaking = new StringBuilder();
        for (JsonNode impact : r.path("impacts")) {
            JsonNode c = impact.path("change");
            if (!"BREAKING".equals(c.path("classification").asText())) {
                continue;
            }
            anyBreaking = true;
            breaking.append("- ");
            String endpoint = c.path("endpoint").asText("");
            if (!endpoint.isEmpty()) {
                breaking.append('`').append(endpoint).append("` — ");
            }
            breaking.append(c.path("description").asText());
            breaking.append('\n');
            String remediation = c.path("remediation").asText("");
            if (!remediation.isEmpty()) {
                breaking.append("  - _Ship it safely:_ ").append(remediation).append('\n');
            }
            for (JsonNode d : impact.path("downstream")) {
                breaking.append("  - 💥 breaks **").append(d.path("consumer").asText()).append("**")
                        .append(teamSuffix(d));
                String field = d.path("matchedField").asText("");
                if (!field.isEmpty()) {
                    breaking.append(" — uses `").append(field).append('`');
                }
                String readiness = readinessSuffix(d);
                if (!readiness.isEmpty()) {
                    breaking.append("   ").append(readiness);
                }
                breaking.append('\n');
            }
        }
        if (anyBreaking) {
            md.append("### 💥 Breaking changes\n").append(breaking).append('\n');
        } else {
            md.append("✅ No breaking changes.\n\n");
        }

        String changelog = r.path("changelog").asText("");
        if (!changelog.isBlank()) {
            md.append("<details><summary>Changelog</summary>\n\n")
                    .append(changelog.trim()).append("\n\n</details>\n");
        }
        return md.toString();
    }

    private static String readinessSuffix(JsonNode consumer) {
        StringBuilder sb = new StringBuilder();
        boolean discovered = consumer.path("discoveredOnly").asBoolean(false);
        if (discovered) {
            sb.append("_discovered — no manifest committed_");
        }
        String lastSeen = consumer.path("lastSeenAt").asText("");
        if (!lastSeen.isEmpty()) {
            if (sb.length() > 0) {
                sb.append(" · ");
            }
            String day = lastSeen.length() >= 10 ? lastSeen.substring(0, 10) : lastSeen;
            sb.append("last seen ").append(day);
        }
        return sb.toString();
    }

    private static String teamSuffix(JsonNode consumer) {
        StringBuilder sb = new StringBuilder();
        String team = consumer.path("ownerTeam").asText("");
        if (!team.isEmpty()) {
            sb.append(" (team ").append(team);
            JsonNode reviewers = consumer.path("reviewers");
            if (reviewers.isArray() && !reviewers.isEmpty()) {
                sb.append(", review: ");
                for (int i = 0; i < reviewers.size(); i++) {
                    if (i > 0) {
                        sb.append(' ');
                    }
                    sb.append('@').append(reviewers.get(i).asText().replace("gh:", ""));
                }
            }
            sb.append(')');
        }
        return sb.toString();
    }
}
