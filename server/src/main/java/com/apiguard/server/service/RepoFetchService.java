package com.apiguard.server.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.stream.Stream;

@Service
public class RepoFetchService {

    private static final Logger log = LoggerFactory.getLogger(RepoFetchService.class);

    private final boolean allowLocalPaths;

    public RepoFetchService(@Value("${apiguard.scan.allow-local-paths:true}") boolean allowLocalPaths) {
        this.allowLocalPaths = allowLocalPaths;
    }

    public record Fetched(Path dir, boolean temporary) {
    }

    public boolean isGitUrl(String source) {
        if (source == null) {
            return false;
        }
        String s = source.trim();
        return s.startsWith("http://") || s.startsWith("https://") || s.startsWith("ssh://")
                || s.startsWith("git://") || s.startsWith("git@") || s.endsWith(".git");
    }

    // A clone URL reaches `git` as an argument, so anything that could be read as an option
    // (`--upload-pack=…`) or as an alternate transport (`ext::sh -c …`) is rejected before it
    // gets there; the `--` separator below is the second line of defence.
    public static void requireSafeCloneUrl(String url) {
        String s = url == null ? "" : url.trim();
        if (s.isEmpty()) {
            throw new IllegalArgumentException("Repo URL is required.");
        }
        if (s.startsWith("-")) {
            throw new IllegalArgumentException("Repo URL must not start with '-'.");
        }
        boolean scpLike = s.startsWith("git@");
        boolean schemed = s.startsWith("http://") || s.startsWith("https://")
                || s.startsWith("ssh://") || s.startsWith("git://");
        if (!scpLike && !schemed) {
            throw new IllegalArgumentException(
                    "Unsupported repo URL. Use http(s)://, ssh://, git:// or git@host:org/repo.");
        }
    }

    // Checked when a source is registered as well as when it is cloned, so a bad URL fails
    // immediately in Sources instead of surfacing as one broken row mid-sync.
    public void validateSource(String source) {
        if (isGitUrl(source)) {
            requireSafeCloneUrl(source);
            return;
        }
        if (!allowLocalPaths) {
            throw new IllegalArgumentException(
                    "Local filesystem paths are disabled on this server "
                            + "(apiguard.scan.allow-local-paths=false). Register a git URL instead.");
        }
    }

    public Fetched fetch(String source) {
        validateSource(source);
        if (!isGitUrl(source)) {
            return new Fetched(Path.of(source), false);
        }
        try {
            Path tmp = Files.createTempDirectory("apiguard-repo-");
            log.info("Cloning {} ...", source.replaceAll("://[^@/]+@", "://***@"));
            runGitClone(source, tmp);
            return new Fetched(tmp, true);
        } catch (IOException e) {
            throw new IllegalArgumentException("Could not prepare a temp dir: " + e.getMessage());
        }
    }

    public void cleanup(Fetched fetched) {
        if (fetched == null || !fetched.temporary()) {
            return;
        }
        try (Stream<Path> walk = Files.walk(fetched.dir())) {
            walk.sorted(Comparator.reverseOrder()).forEach(p -> {
                try {
                    Files.deleteIfExists(p);
                } catch (IOException ignored) {
                }
            });
        } catch (IOException ignored) {
        }
    }

    private static final int CLONE_TIMEOUT_SECONDS = 120;

    private void runGitClone(String url, Path target) {
        Path logFile = null;
        try {
            logFile = Files.createTempFile("apiguard-clone-", ".log");
            ProcessBuilder pb = new ProcessBuilder(
                    "git", "clone", "--depth", "1", "--no-tags", "--", url, target.toString());

            pb.environment().put("GIT_TERMINAL_PROMPT", "0");
            pb.environment().put("GCM_INTERACTIVE", "Never");
            pb.environment().put("GIT_ASKPASS", "echo");

            pb.redirectErrorStream(true);
            pb.redirectOutput(logFile.toFile());
            Process p = pb.start();

            if (!p.waitFor(CLONE_TIMEOUT_SECONDS, java.util.concurrent.TimeUnit.SECONDS)) {
                p.destroyForcibly();
                throw new IllegalArgumentException(
                        "git clone timed out after " + CLONE_TIMEOUT_SECONDS + "s — check the URL is a reachable git repo"
                                + " (a GitHub profile/search page is not cloneable).");
            }
            if (p.exitValue() != 0) {
                String output = Files.readString(logFile).replaceAll("://[^@/]+@", "://***@").strip();
                throw new IllegalArgumentException("git clone failed: "
                        + (output.isBlank() ? "not a git repository, or access denied" : output));
            }
        } catch (IOException e) {
            throw new IllegalArgumentException("git not available or clone failed: " + e.getMessage());
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalArgumentException("clone interrupted");
        } finally {
            if (logFile != null) {
                try {
                    Files.deleteIfExists(logFile);
                } catch (IOException ignored) {
                }
            }
        }
    }
}
