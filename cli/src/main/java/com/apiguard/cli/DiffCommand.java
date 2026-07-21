package com.apiguard.cli;

import com.apiguard.core.changelog.ChangelogGenerator;
import com.apiguard.core.diff.Change;
import com.apiguard.core.diff.DiffEngine;
import com.apiguard.core.spec.SpecLoader;
import io.swagger.v3.oas.models.OpenAPI;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;
import picocli.CommandLine.Parameters;

import java.nio.file.Path;
import java.util.Comparator;
import java.util.List;
import java.util.concurrent.Callable;

@Command(name = "diff", mixinStandardHelpOptions = true,
        description = "Diff two OpenAPI specs and classify each change as BREAKING / SAFE / ADDITIVE.")
public final class DiffCommand implements Callable<Integer> {

    @Parameters(index = "0", paramLabel = "OLD_OR_NEW", arity = "1",
            description = "Baseline spec path; or, with --base, the current spec to compare against git history.")
    Path firstSpec;

    @Parameters(index = "1", paramLabel = "NEW", arity = "0..1",
            description = "New spec path (omit when using --base).")
    Path newSpecOpt;

    @Option(names = "--base", description = "Git ref (e.g. main) to read the baseline spec from, instead of an OLD file.")
    String baseRef;

    @Option(names = "--changelog", description = "Also print a categorized Markdown changelog.")
    boolean changelog;

    @Option(names = "--fail-on-breaking", description = "Exit with code 1 if any breaking change is found.")
    boolean failOnBreaking;

    @Option(names = "--no-color", description = "Disable ANSI colour output.")
    boolean noColor;

    @Override
    public Integer call() {
        Ansi ansi = new Ansi(!noColor);
        OpenAPI oldApi;
        OpenAPI newApi;
        if (baseRef != null) {

            newApi = SpecLoader.loadFile(firstSpec);
            oldApi = SpecLoader.loadString(GitSpec.showAtRef(firstSpec, baseRef));
        } else {
            if (newSpecOpt == null) {
                System.err.println("Provide NEW spec, or use --base <ref>.");
                return 2;
            }
            oldApi = SpecLoader.loadFile(firstSpec);
            newApi = SpecLoader.loadFile(newSpecOpt);
        }

        List<Change> changes = new DiffEngine().diff(oldApi, newApi).stream()
                .sorted(Comparator.comparing((Change c) -> c.classification().ordinal())
                        .thenComparing(c -> c.endpoint() == null ? "" : c.endpoint()))
                .toList();

        CliOutput.printChanges(ansi, changes);

        var bump = com.apiguard.core.diff.VersionAdvisor.recommend(changes);
        if (bump != com.apiguard.core.diff.VersionAdvisor.Bump.NONE) {
            String current = newApi.getInfo() != null ? newApi.getInfo().getVersion() : null;
            String next = com.apiguard.core.diff.VersionAdvisor.nextVersion(current, bump);
            System.out.println(ansi.dim("Recommended version bump: ") + ansi.bold(bump.name())
                    + (current != null && next != null ? ansi.dim("  (" + current + " -> " + next + ")") : ""));
        }

        if (changelog) {
            System.out.println();
            System.out.println(ansi.dim("──── changelog ────"));
            System.out.println(new ChangelogGenerator().generate(changes));
        }

        long breaking = changes.stream().filter(Change::isBreaking).count();
        return (failOnBreaking && breaking > 0) ? 1 : 0;
    }
}
