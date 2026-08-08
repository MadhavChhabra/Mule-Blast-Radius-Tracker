# One self-contained image: the Flutter dashboard is built first and bundled into the server jar,
# so a single container serves both the UI and the API on port 8080 (same origin, no CORS).

FROM ghcr.io/cirruslabs/flutter:3.24.3 AS ui
WORKDIR /src/dashboard
COPY dashboard/pubspec.yaml dashboard/pubspec.lock ./
RUN flutter pub get
COPY dashboard/ ./
# The HTML renderer keeps the app self-contained; CanvasKit would fetch its wasm from a CDN at
# runtime, which fails on air-gapped or egress-filtered enterprise networks.
RUN flutter build web --release --web-renderer html

FROM gradle:8.10-jdk17 AS build
WORKDIR /src
COPY . .
COPY --from=ui /src/dashboard/build/web /src/dashboard/build/web
RUN gradle :server:bootJar --no-daemon

FROM eclipse-temurin:17-jre
RUN groupadd --system --gid 10001 wakegraph \
    && useradd --system --uid 10001 --gid wakegraph --home /app wakegraph \
    && apt-get update \
    && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build --chown=wakegraph:wakegraph /src/server/build/libs/*.jar /app/server.jar
USER wakegraph
EXPOSE 8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -fsS http://localhost:8080/api/health || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/server.jar"]
