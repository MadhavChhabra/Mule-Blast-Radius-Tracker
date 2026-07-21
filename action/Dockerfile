# Multi-stage: build the fat jar with Gradle, then ship a slim JRE runtime.
FROM gradle:8.10-jdk17 AS build
WORKDIR /src
COPY . .
RUN gradle :cli:shadowJar --no-daemon

FROM eclipse-temurin:17-jre
RUN apt-get update && apt-get install -y --no-install-recommends curl jq git \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/cli/build/libs/apiguard.jar /app/apiguard.jar
COPY action/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
