package com.apiguard.cli;

import picocli.CommandLine.Command;
import picocli.CommandLine.Option;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.util.Locale;
import java.util.concurrent.Callable;

@Command(name = "init", mixinStandardHelpOptions = true,
        description = "Enroll this repo in Wakegraph: writes .wakegraph.yml and a CI workflow that runs `wakegraph impact` on every PR touching the spec.")
public final class InitCommand implements Callable<Integer> {

    @Option(names = {"-a", "--api"}, required = true,
            description = "API name in the estate (assetId / Maven artifactId).")
    String apiName;

    @Option(names = {"-s", "--spec"}, required = true,
            description = "Path to the OpenAPI/RAML spec inside this repo (e.g. src/main/resources/api/orders.raml).")
    String specPath;

    @Option(names = "--server",
            description = "Wakegraph server base URL that CI will call.",
            defaultValue = "https://wakegraph.internal")
    String server;

    @Option(names = "--base", description = "Base branch for PR diffs. Default: main.",
            defaultValue = "main")
    String baseBranch;

    @Option(names = "--ci", description = "CI target: github (default) or bitbucket.",
            defaultValue = "github")
    String ci;

    @Option(names = "--api-key-secret",
            description = "Name of the CI secret that holds the Wakegraph API key. Default: WAKEGRAPH_API_KEY.",
            defaultValue = "WAKEGRAPH_API_KEY")
    String apiKeySecret;

    @Option(names = {"-C", "--dir"}, description = "Repository root. Default: current directory.",
            defaultValue = ".")
    Path repoRoot;

    @Option(names = "--force", description = "Overwrite existing config / workflow files.")
    boolean force;

    @Option(names = "--no-color", description = "Disable ANSI colour output.")
    boolean noColor;

    @Override
    public Integer call() throws IOException {
        Ansi ansi = new Ansi(!noColor);
        Path root = repoRoot.toAbsolutePath().normalize();
        if (!Files.isDirectory(root)) {
            System.err.println("Not a directory: " + root);
            return 2;
        }

        Path spec = root.resolve(specPath);
        if (!Files.isRegularFile(spec)) {
            System.err.println(ansi.yellow("Warning: spec not found at " + spec
                    + " — continuing anyway (path is written to .wakegraph.yml as-is)."));
        }

        String target = ci.toLowerCase(Locale.ROOT);
        if (!target.equals("github") && !target.equals("bitbucket")) {
            System.err.println("--ci must be github or bitbucket.");
            return 2;
        }

        Path config = root.resolve(".wakegraph.yml");
        boolean configWritten = writeIfAbsent(config, projectConfig(), ansi);

        Path workflow;
        String workflowBody;
        if (target.equals("github")) {
            workflow = root.resolve(".github").resolve("workflows").resolve("wakegraph.yml");
            workflowBody = githubWorkflow();
        } else {
            workflow = root.resolve("bitbucket-pipelines.yml");
            workflowBody = bitbucketPipeline();
        }
        boolean workflowWritten = writeIfAbsent(workflow, workflowBody, ansi);

        System.out.println();
        System.out.println(ansi.bold("Wakegraph enrolled."));
        System.out.println("  config    " + rel(root, config) + (configWritten ? "" : ansi.dim("  (kept)")));
        System.out.println("  workflow  " + rel(root, workflow) + (workflowWritten ? "" : ansi.dim("  (kept)")));
        System.out.println();
        System.out.println("Next steps:");
        System.out.println("  1. Add the CI secret " + ansi.bold(apiKeySecret)
                + " if your Wakegraph server has API-key auth on.");
        System.out.println("  2. Commit the two files above.");
        System.out.println("  3. Open a PR that changes " + ansi.bold(specPath)
                + " and Wakegraph will comment with the blast radius.");
        return 0;
    }

    private boolean writeIfAbsent(Path path, String body, Ansi ansi) throws IOException {
        Files.createDirectories(path.getParent() == null ? path : path.getParent());
        if (Files.exists(path) && !force) {
            System.out.println(ansi.dim("Skipped ") + path + ansi.dim(" — exists (use --force to overwrite)."));
            return false;
        }
        Files.writeString(path, body, StandardCharsets.UTF_8,
                StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING);
        return true;
    }

    private static String rel(Path root, Path p) {
        try {
            return root.relativize(p).toString().replace('\\', '/');
        } catch (IllegalArgumentException e) {
            return p.toString();
        }
    }

    private String projectConfig() {
        return "" +
                "# Wakegraph project config — committed to the repo, read by CI.\n" +
                "api: " + apiName + "\n" +
                "spec: " + specPath + "\n" +
                "base: " + baseBranch + "\n" +
                "server: " + server + "\n" +
                "apiKeySecret: " + apiKeySecret + "\n" +
                "# failOn: breaking-impact   # breaking-impact | breaking | never\n";
    }

    private String githubWorkflow() {
        return "" +
                "name: Wakegraph\n" +
                "on:\n" +
                "  pull_request:\n" +
                "    paths:\n" +
                "      - '" + specPath + "'\n" +
                "      - '.wakegraph.yml'\n" +
                "jobs:\n" +
                "  impact:\n" +
                "    runs-on: ubuntu-latest\n" +
                "    permissions:\n" +
                "      contents: read\n" +
                "      pull-requests: write\n" +
                "    steps:\n" +
                "      - uses: actions/checkout@v4\n" +
                "        with: { fetch-depth: 0 }\n" +
                "      - uses: MadhavChhabra/Mule-Blast-Radius-Tracker/action@main\n" +
                "        with:\n" +
                "          old-spec: /tmp/old-spec\n" +
                "          new-spec: " + specPath + "\n" +
                "          api: " + apiName + "\n" +
                "          server: " + server + "\n" +
                "          fail-on-breaking: 'true'\n" +
                "        env:\n" +
                "          APIGUARD_API_KEY: ${{ secrets." + apiKeySecret + " }}\n" +
                "      # The action's entrypoint reads --base " + baseBranch + " when old-spec is missing.\n";
    }

    private String bitbucketPipeline() {
        return "" +
                "# Wakegraph impact — runs on every PR touching " + specPath + "\n" +
                "image: eclipse-temurin:17\n" +
                "pipelines:\n" +
                "  pull-requests:\n" +
                "    '**':\n" +
                "      - step:\n" +
                "          name: Wakegraph impact\n" +
                "          script:\n" +
                "            - test -f cli/build/libs/apiguard.jar || (curl -sSL -o wakegraph.jar\n" +
                "                https://github.com/MadhavChhabra/Mule-Blast-Radius-Tracker/releases/latest/download/apiguard.jar)\n" +
                "            - JAR=${JAR:-wakegraph.jar}\n" +
                "            - java -jar \"$JAR\" impact " + specPath
                + " --base origin/" + baseBranch + " --api " + apiName + "\n"
                + "                --server \"$WAKEGRAPH_SERVER\" --markdown wakegraph-report.md\n" +
                "                --fail-on breaking-impact\n" +
                "          artifacts:\n" +
                "            - wakegraph-report.md\n" +
                "definitions:\n" +
                "  # Configure repository variables:\n" +
                "  #   WAKEGRAPH_SERVER  = " + server + "\n" +
                "  #   APIGUARD_API_KEY  = <secret from " + apiKeySecret + ">\n" +
                "  services: {}\n";
    }
}
