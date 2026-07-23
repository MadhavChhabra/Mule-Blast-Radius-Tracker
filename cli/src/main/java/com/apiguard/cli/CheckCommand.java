package com.apiguard.cli;

import com.apiguard.core.blast.BlastRadiusResolver;
import com.apiguard.core.blast.ManifestLoader;
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

@Command(name = "check", mixinStandardHelpOptions = true,
        description = "Diff two specs and report the blast radius (downstream consumers + upstream sources). "
                + "With one spec and no --base, compares your working copy against main/master.")
public final class CheckCommand implements Callable<Integer> {

    @Parameters(index = "0", paramLabel = "OLD_OR_NEW", arity = "1",
            description = "Baseline spec path; or, with --base (or alone), the current spec to compare against git history.")
    Path firstSpec;

    @Parameters(index = "1", paramLabel = "NEW", arity = "0..1",
            description = "New spec path (omit to compare the first spec against git history).")
    Path newSpecOpt;

    @Option(names = "--base", description = "Git ref (e.g. main) to read the baseline spec from. Defaults to main/master when NEW is omitted.")
    String baseRef;

    @Option(names = {"-a", "--api"},
            description = "Name of the API being changed (matches the 'api' key in manifests). Inferred from the spec title if omitted.")
    String apiName;

    @Option(names = {"-m", "--manifests"}, description = "Directory to scan for apiguard-deps.yaml / apiguard-sources.yaml. Default: current dir.")
    Path manifests = Path.of(".");

    @Option(names = "--mule", description = "Auto-discover consumers from Mule project(s) in this dir (pom.xml + flow XML). No manifests needed.")
    Path muleDir;

    @Option(names = "--strict", description = "Fail on ANY breaking change, even without an impacted consumer.")
    boolean strict;

    @Option(names = "--no-color", description = "Disable ANSI colour output.")
    boolean noColor;

    @Override
    public Integer call() {
        Ansi ansi = new Ansi(!noColor);

        OpenAPI oldApi;
        OpenAPI newApi;
        if (newSpecOpt == null && baseRef == null) {
            baseRef = GitSpec.resolveDefaultBase(firstSpec);
            if (baseRef == null) {
                System.err.println("Provide a NEW spec, or run inside a git repo (needs a main/master branch), or pass --base <ref>.");
                return 2;
            }
            System.out.println(ansi.dim("Comparing working copy against " + baseRef));
        }
        if (baseRef != null) {
            newApi = SpecLoader.loadFile(firstSpec);
            oldApi = SpecLoader.loadString(GitSpec.showAtRef(firstSpec, baseRef));
        } else {
            oldApi = SpecLoader.loadFile(firstSpec);
            newApi = SpecLoader.loadFile(newSpecOpt);
        }

        if (apiName == null || apiName.isBlank()) {
            apiName = inferApiName(newApi, firstSpec);
            System.out.println(ansi.dim("API name (inferred): " + apiName));
        }
        List<Change> changes = new DiffEngine().diff(oldApi, newApi).stream()
                .sorted(Comparator.comparing((Change c) -> c.classification().ordinal())
                        .thenComparing(c -> c.endpoint() == null ? "" : c.endpoint()))
                .toList();

        ManifestLoader.Loaded loaded = ManifestLoader.discover(manifests);
        List<com.apiguard.core.blast.DependencyManifest> allConsumers =
                new java.util.ArrayList<>(loaded.consumers());

        int discovered = 0;
        if (muleDir != null) {
            var scans = com.apiguard.core.mule.MuleProjectScanner.scanAll(muleDir);
            for (var scan : scans) {
                allConsumers.add(scan.toManifest());
            }
            discovered = scans.size();
        }

        System.out.println(ansi.dim("Loaded " + loaded.consumers().size() + " manifest consumer(s)"
                + (discovered > 0 ? " + " + discovered + " auto-discovered Mule app(s)" : "")
                + ", " + loaded.sources().size() + " source manifest(s)"));
        System.out.println();

        BlastRadiusResolver resolver = new BlastRadiusResolver(allConsumers, loaded.sources());
        List<BlastRadiusResolver.Impact> impacts = resolver.resolve(apiName, changes);

        CliOutput.printImpacts(ansi, impacts);

        long breakingWithConsumers = impacts.stream()
                .filter(i -> i.change().isBreaking() && !i.downstream().isEmpty())
                .count();
        long anyBreaking = changes.stream().filter(Change::isBreaking).count();

        long additive = changes.stream().filter(c -> c.classification() == com.apiguard.core.diff.Classification.ADDITIVE).count();
        long impactedConsumers = impacts.stream().filter(i -> i.change().isBreaking())
                .flatMap(i -> i.downstream().stream())
                .map(BlastRadiusResolver.ConsumerImpact::consumer).distinct().count();
        var risk = com.apiguard.core.blast.RiskScorer.score((int) anyBreaking, (int) additive, (int) impactedConsumers);
        var bump = com.apiguard.core.diff.VersionAdvisor.recommend(changes);
        System.out.println();
        String riskLine = "Deployment risk: " + risk.level() + " (" + risk.score() + "/100)   "
                + "Recommended bump: " + bump.name();
        System.out.println(risk.level() == com.apiguard.core.blast.RiskScorer.Level.CRITICAL
                || risk.level() == com.apiguard.core.blast.RiskScorer.Level.HIGH
                ? ansi.red(ansi.bold(riskLine)) : ansi.yellow(riskLine));

        System.out.println();
        if (breakingWithConsumers > 0) {
            long consumers = impacts.stream()
                    .filter(i -> i.change().isBreaking())
                    .flatMap(i -> i.downstream().stream())
                    .map(BlastRadiusResolver.ConsumerImpact::consumer).distinct().count();
            System.out.println(ansi.red(ansi.bold(breakingWithConsumers + " breaking change(s) affecting "
                    + consumers + " consumer(s) -> exit 1")));
            return 1;
        }
        if (strict && anyBreaking > 0) {
            System.out.println(ansi.red(ansi.bold(anyBreaking + " breaking change(s), --strict -> exit 1")));
            return 1;
        }
        System.out.println(ansi.green("No breaking changes hit a known consumer."));
        return 0;
    }

    static String inferApiName(OpenAPI api, Path specPath) {
        String title = api != null && api.getInfo() != null ? api.getInfo().getTitle() : null;
        String slug = slug(title);
        if (!slug.isBlank()) {
            return slug;
        }
        String file = specPath.getFileName() == null ? "api" : specPath.getFileName().toString();
        int dot = file.lastIndexOf('.');
        slug = slug(dot > 0 ? file.substring(0, dot) : file);
        return slug.isBlank() ? "api" : slug;
    }

    private static String slug(String s) {
        if (s == null) {
            return "";
        }
        return s.toLowerCase(java.util.Locale.ROOT)
                .replaceAll("[^a-z0-9]+", "-")
                .replaceAll("^-+|-+$", "");
    }
}
