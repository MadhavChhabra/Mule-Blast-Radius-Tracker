package com.apiguard.cli;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import picocli.CommandLine;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class InitCommandTest {

    @Test
    void writesGithubWorkflowAndConfig(@TempDir Path root) throws Exception {
        int exit = new CommandLine(new InitCommand()).execute(
                "--api", "orders-exp-api",
                "--spec", "src/main/resources/api/orders.raml",
                "--server", "https://wakegraph.example",
                "--dir", root.toString(),
                "--no-color");
        assertEquals(0, exit);

        Path config = root.resolve(".wakegraph.yml");
        Path workflow = root.resolve(".github/workflows/wakegraph.yml");
        assertTrue(Files.exists(config), "config file");
        assertTrue(Files.exists(workflow), "workflow file");

        String cfg = Files.readString(config);
        assertTrue(cfg.contains("api: orders-exp-api"), cfg);
        assertTrue(cfg.contains("spec: src/main/resources/api/orders.raml"), cfg);
        assertTrue(cfg.contains("server: https://wakegraph.example"), cfg);
        assertTrue(cfg.contains("apiKeySecret: WAKEGRAPH_API_KEY"), cfg);

        String wf = Files.readString(workflow);
        assertTrue(wf.contains("on:") && wf.contains("pull_request:"), wf);
        assertTrue(wf.contains("- 'src/main/resources/api/orders.raml'"), wf);
        assertTrue(wf.contains("api: orders-exp-api"), wf);
        assertTrue(wf.contains("secrets.WAKEGRAPH_API_KEY"), wf);
    }

    @Test
    void bitbucketPipelineTarget(@TempDir Path root) throws Exception {
        int exit = new CommandLine(new InitCommand()).execute(
                "--api", "orders-exp-api",
                "--spec", "specs/orders.raml",
                "--ci", "bitbucket",
                "--dir", root.toString(),
                "--no-color");
        assertEquals(0, exit);

        Path pipe = root.resolve("bitbucket-pipelines.yml");
        assertTrue(Files.exists(pipe));
        String body = Files.readString(pipe);
        assertTrue(body.contains("pipelines:"), body);
        assertTrue(body.contains("\"$JAR\" impact"), body);
        assertTrue(body.contains("--api orders-exp-api"), body);
    }

    @Test
    void skipsExistingUnlessForce(@TempDir Path root) throws Exception {
        Path config = root.resolve(".wakegraph.yml");
        Files.writeString(config, "keep: me\n");

        int exit = new CommandLine(new InitCommand()).execute(
                "--api", "a", "--spec", "s.raml",
                "--dir", root.toString(), "--no-color");
        assertEquals(0, exit);
        assertEquals("keep: me\n", Files.readString(config));

        int exit2 = new CommandLine(new InitCommand()).execute(
                "--api", "a", "--spec", "s.raml",
                "--dir", root.toString(), "--no-color", "--force");
        assertEquals(0, exit2);
        assertFalse(Files.readString(config).equals("keep: me\n"), "force should overwrite");
    }
}
