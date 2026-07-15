package com.apiguard.core.catalog;

/**
 * MuleSoft API-led connectivity layer. Every node in the estate map sits in one of these tiers, so
 * the graph can be organised the way MuleSoft teams actually think: apps call Experience APIs, which
 * call Process APIs, which call System APIs.
 *
 * <p>Classification is by naming convention (the reliable signal in a Mule estate). Anypoint tags or
 * categories can override it later.
 */
public enum ApiLayer {
    EXPERIENCE("Experience API"),
    PROCESS("Process API"),
    SYSTEM("System API"),
    BACKEND("System of record"),
    APP("Consumer app"),
    UNKNOWN("API");

    private final String label;

    ApiLayer(String label) {
        this.label = label;
    }

    public String label() {
        return label;
    }

    public boolean isApi() {
        return this != APP;
    }

    /**
     * Classify by name. System/Process/Experience are checked before "app" because names like
     * {@code hr-portal-sys-api} contain both an app-ish word and a system suffix — the tier wins.
     */
    public static ApiLayer classify(String name) {
        if (name == null || name.isBlank()) {
            return UNKNOWN;
        }
        String n = name.toLowerCase().replace('_', '-');

        // End systems / systems of record (databases, SaaS, queues, files) — a Mule app calls these
        // through a connector, not an HTTP API, but they are the true producers at the bottom of the
        // chain. Checked first, with token-safe matching so "sap" never swallows "orders-sapi".
        if (isBackend(n)) {
            return BACKEND;
        }
        if (containsAny(n, "sys-api", "system-api", "systemapi", "-sapi", "-sys") || n.endsWith("sapi")
                || n.endsWith("-system") || n.contains("system")) {
            return SYSTEM;
        }
        if (containsAny(n, "process-api", "-papi", "prc-api", "-prc", "processapi", "proc-api") || n.endsWith("papi")
                || n.contains("process") || n.contains("-proc")) {
            return PROCESS;
        }
        if (containsAny(n, "experience-api", "exp-api", "-eapi", "-xapi", "-exp-", "expapi") || n.endsWith("eapi")
                || n.endsWith("-exp") || n.endsWith("-xapi") || n.contains("experience")) {
            return EXPERIENCE;
        }
        if (containsAny(n, "-app", "application", "-poc", "portal", "-web", "mobile", "-client", "frontend")
                || n.endsWith("app") || n.endsWith("-ui")) {
            return APP;
        }
        return UNKNOWN;
    }

    /**
     * A system of record: databases, SaaS end systems, queues and file systems. Matches the canonical
     * names the Mule scanner emits for connector calls plus common database engines. Token-safe for
     * {@code sap} (must be standalone or hyphenated) so it doesn't collide with the {@code sapi} suffix.
     */
    private static boolean isBackend(String n) {
        if (containsAny(n, "database", "salesforce", "netsuite", "workday", "servicenow",
                "kafka", "mongodb", "mongo", "dynamodb", "cassandra", "redis",
                "jms", "amqp", "rabbitmq", "activemq", "sqs", " queue", "-queue",
                "oracle", "mysql", "postgres", "postgresql", "mariadb", "mssql", "sqlserver", "db2",
                "mainframe", "as400", "ftp", "sftp", "file system", "file-system",
                "smtp", "email", "object store")) {
            return true;
        }
        // "sap" only as a standalone token / hyphenated segment (not inside "sapi").
        return n.equals("sap") || n.startsWith("sap-") || n.endsWith("-sap") || n.contains("-sap-")
                || n.startsWith("sap ") || n.endsWith("-db") || n.endsWith("-database");
    }

    private static boolean containsAny(String s, String... needles) {
        for (String needle : needles) {
            if (s.contains(needle)) {
                return true;
            }
        }
        return false;
    }
}
