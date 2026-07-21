package com.apiguard.core.catalog;

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

    public static ApiLayer classify(String name) {
        if (name == null || name.isBlank()) {
            return UNKNOWN;
        }
        String n = name.toLowerCase().replace('_', '-');

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

    private static boolean isBackend(String n) {
        if (containsAny(n, "database", "salesforce", "netsuite", "workday", "servicenow",
                "kafka", "mongodb", "mongo", "dynamodb", "cassandra", "redis",
                "jms", "amqp", "rabbitmq", "activemq", "sqs", " queue", "-queue",
                "oracle", "mysql", "postgres", "postgresql", "mariadb", "mssql", "sqlserver", "db2",
                "mainframe", "as400", "ftp", "sftp", "file system", "file-system",
                "smtp", "email", "object store")) {
            return true;
        }

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
