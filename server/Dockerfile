# One self-contained image: the Flutter dashboard is built first and bundled into the server jar,
# so a single container serves both the UI and the API on port 8080 (same origin, no CORS).

FROM ghcr.io/cirruslabs/flutter:3.24.3 AS ui
WORKDIR /src/dashboard
COPY dashboard/pubspec.yaml dashboard/pubspec.lock ./
RUN flutter pub get
COPY dashboard/ ./
# CanvasKit with --no-web-resources-cdn: the wasm is served from our own /canvaskit/, so nothing is
# fetched from gstatic at runtime and the app works on air-gapped or egress-filtered networks. The
# HTML renderer would also be self-contained but cannot do BackdropFilter, which the glass panels
# throughout the UI depend on — this keeps Docker rendering identical to the desktop build.
RUN flutter build web --release --web-renderer canvaskit --no-web-resources-cdn

FROM gradle:8.10-jdk17 AS build
WORKDIR /src
COPY . .
COPY --from=ui /src/dashboard/build/web /src/dashboard/build/web
RUN gradle :server:bootJar --no-daemon

FROM eclipse-temurin:17-jre
RUN groupadd --system --gid 10001 blipradius \
    && useradd --system --uid 10001 --gid blipradius --home /app blipradius \
    && apt-get update \
    && apt-get install -y --no-install-recommends git curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
# Named exactly, not globbed: `libs/*.jar` would match the plain jar too the moment anything runs
# `jar`, and Docker fails a multi-source COPY into a single file with a confusing message.
COPY --from=build --chown=blipradius:blipradius /src/server/build/libs/blipradius-server.jar /app/server.jar
USER blipradius
EXPOSE 8080
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=5 \
    CMD curl -fsS http://localhost:8080/api/health || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/server.jar"]
