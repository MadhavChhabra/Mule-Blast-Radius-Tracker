package com.apiguard.cli;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

final class GitSpec {

    private GitSpec() {
    }

    static String showAtRef(Path specPath, String baseRef) {
        Path abs = specPath.toAbsolutePath().normalize();
        String topLevel = runGitRaw(abs.getParent(), "rev-parse", "--show-toplevel");
        if (topLevel == null) {
            throw new IllegalStateException("Not inside a git repository: " + abs.getParent());
        }
        Path root = Path.of(topLevel.strip());
        String relative = root.relativize(abs).toString().replace('\\', '/');

        String content = runGitRaw(abs.getParent(), "show", baseRef + ":" + relative);
        if (content == null) {
            throw new IllegalArgumentException(
                    "Could not read '" + relative + "' at ref '" + baseRef + "'. Is it committed there?");
        }
        return content;
    }

    private static String runGitRaw(Path cwd, String... args) {
        try {
            String[] cmd = new String[args.length + 1];
            cmd[0] = "git";
            System.arraycopy(args, 0, cmd, 1, args.length);
            ProcessBuilder pb = new ProcessBuilder(cmd);
            if (cwd != null) {
                pb.directory(cwd.toFile());
            }
            pb.redirectErrorStream(false);
            Process p = pb.start();
            ByteArrayOutputStream buf = new ByteArrayOutputStream();
            p.getInputStream().transferTo(buf);
            int code = p.waitFor();
            if (code != 0) {
                return null;
            }
            return buf.toString(StandardCharsets.UTF_8);
        } catch (Exception e) {
            return null;
        }
    }
}
