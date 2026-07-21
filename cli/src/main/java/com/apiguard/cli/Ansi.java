package com.apiguard.cli;

import com.apiguard.core.diff.Classification;

final class Ansi {

    private static final String ESC = "";
    private static final String RESET = ESC + "[0m";
    private static final String RED = ESC + "[31m";
    private static final String GREEN = ESC + "[32m";
    private static final String YELLOW = ESC + "[33m";
    private static final String CYAN = ESC + "[36m";
    private static final String BOLD = ESC + "[1m";
    private static final String DIM = ESC + "[2m";

    private final boolean enabled;

    Ansi(boolean enabled) {
        this.enabled = enabled && System.getenv("NO_COLOR") == null;
    }

    private String wrap(String code, String s) {
        return enabled ? code + s + RESET : s;
    }

    String red(String s) {
        return wrap(RED, s);
    }

    String green(String s) {
        return wrap(GREEN, s);
    }

    String yellow(String s) {
        return wrap(YELLOW, s);
    }

    String cyan(String s) {
        return wrap(CYAN, s);
    }

    String bold(String s) {
        return wrap(BOLD, s);
    }

    String dim(String s) {
        return wrap(DIM, s);
    }

    String classification(Classification c) {
        return switch (c) {
            case BREAKING -> red(bold(String.format("%-9s", "BREAKING")));
            case NON_BREAKING -> yellow(String.format("%-9s", "SAFE"));
            case ADDITIVE -> green(String.format("%-9s", "ADDITIVE"));
        };
    }
}
