package com.apiguard.core.diff;

import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Recommends a semantic-version bump from a classified diff:
 * <ul>
 *   <li>any {@link Classification#BREAKING} → <b>MAJOR</b></li>
 *   <li>otherwise any {@link Classification#ADDITIVE} → <b>MINOR</b></li>
 *   <li>otherwise any change at all → <b>PATCH</b></li>
 *   <li>no changes → <b>NONE</b></li>
 * </ul>
 */
public final class VersionAdvisor {

    public enum Bump {MAJOR, MINOR, PATCH, NONE}

    private static final Pattern SEMVER = Pattern.compile("^[vV]?(\\d+)\\.(\\d+)\\.(\\d+)(.*)$");

    private VersionAdvisor() {
    }

    public static Bump recommend(List<Change> changes) {
        if (changes.isEmpty()) {
            return Bump.NONE;
        }
        boolean breaking = false;
        boolean additive = false;
        for (Change c : changes) {
            if (c.classification() == Classification.BREAKING) {
                breaking = true;
            } else if (c.classification() == Classification.ADDITIVE) {
                additive = true;
            }
        }
        if (breaking) {
            return Bump.MAJOR;
        }
        return additive ? Bump.MINOR : Bump.PATCH;
    }

    /**
     * Apply a bump to a semver string, preserving a leading {@code v} if present. Returns
     * {@code null} when the current version is not semver-parseable (then only the bump is advised).
     */
    public static String nextVersion(String current, Bump bump) {
        if (current == null || bump == Bump.NONE) {
            return null;
        }
        Matcher m = SEMVER.matcher(current.trim());
        if (!m.matches()) {
            return null;
        }
        int major = Integer.parseInt(m.group(1));
        int minor = Integer.parseInt(m.group(2));
        int patch = Integer.parseInt(m.group(3));
        switch (bump) {
            case MAJOR -> {
                major++;
                minor = 0;
                patch = 0;
            }
            case MINOR -> {
                minor++;
                patch = 0;
            }
            case PATCH -> patch++;
            default -> {
                return null;
            }
        }
        String prefix = current.trim().startsWith("v") ? "v" : current.trim().startsWith("V") ? "V" : "";
        return prefix + major + "." + minor + "." + patch;
    }
}
