package com.apiguard.server.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Stream;

/// Finds Mule projects already sitting on this machine, so the desktop app can offer "scan what you
/// already have" instead of demanding a URL and a token before it shows anything.
@Service
public class WorkspaceScoutService {

    private static final Logger log = LoggerFactory.getLogger(WorkspaceScoutService.class);

    // Deep enough for the usual <root>/<repo>/<module>/pom.xml and a nested multi-module layout.
    private static final int MAX_DEPTH = 6;
    private static final int MAX_RESULTS = 50;

    private final boolean enabled;

    public WorkspaceScoutService(@Value("${apiguard.scan.allow-local-paths:true}") boolean enabled) {
        this.enabled = enabled;
    }

    public record Candidate(String path, String name, int projects) {
    }

    /// Directories people actually keep MuleSoft work in. Nothing is scanned or stored — this only
    /// reports what a later "Add" would pick up.
    private static List<Path> roots() {
        String home = System.getProperty("user.home");
        List<Path> roots = new ArrayList<>();
        if (home != null && !home.isBlank()) {
            Path h = Path.of(home);
            roots.add(h.resolve("AnypointStudio/studio-workspace"));
            roots.add(h.resolve("AnypointStudio"));
            roots.add(h.resolve("workspace"));
            roots.add(h.resolve("git"));
            roots.add(h.resolve("source"));
            roots.add(h.resolve("Projects"));
            roots.add(h.resolve("projects"));
            roots.add(h.resolve("repos"));
            roots.add(h.resolve("Documents/GitHub"));
        }
        return roots;
    }

    public List<Candidate> discover() {
        if (!enabled) {
            return List.of();
        }
        List<Candidate> found = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (Path root : roots()) {
            if (!Files.isDirectory(root) || !seen.add(root.toString())) {
                continue;
            }
            int projects = countMuleProjects(root);
            if (projects > 0) {
                found.add(new Candidate(root.toString(), root.getFileName().toString(), projects));
            }
            if (found.size() >= MAX_RESULTS) {
                break;
            }
        }
        log.debug("Workspace scout found {} candidate director(ies).", found.size());
        return found;
    }

    private static int countMuleProjects(Path root) {
        try (Stream<Path> walk = Files.walk(root, MAX_DEPTH)) {
            return (int) walk
                    .filter(p -> p.getFileName() != null && p.getFileName().toString().equals("pom.xml"))
                    .map(Path::getParent)
                    .filter(dir -> dir != null && Files.isDirectory(dir.resolve("src/main/mule")))
                    .limit(MAX_RESULTS)
                    .count();
        } catch (IOException | RuntimeException e) {
            return 0;
        }
    }
}
