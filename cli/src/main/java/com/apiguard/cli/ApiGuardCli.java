package com.apiguard.cli;

import picocli.CommandLine;
import picocli.CommandLine.Command;

import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

@Command(
        name = "wakegraph",
        mixinStandardHelpOptions = true,
        version = "Wakegraph 0.1.0",
        description = "Wakegraph — see the blast radius of an API change: detect breaking changes, map real dependencies, write changelogs.",
        subcommands = {DiffCommand.class, CheckCommand.class, ScanCommand.class, ImpactCommand.class,
                ReportCommand.class, InitCommand.class}
)
public final class ApiGuardCli implements Runnable {

    @Override
    public void run() {

        new CommandLine(this).usage(System.out);
    }

    public static void main(String[] args) {

        System.setOut(new PrintStream(System.out, true, StandardCharsets.UTF_8));
        int exit = new CommandLine(new ApiGuardCli()).execute(args);
        System.exit(exit);
    }
}
