# Wakegraph

Wakegraph (formerly APIGuard, then FlowSight — renamed 2026-07-15 because FlowSight collides with
an existing product; internal Java package is still `com.apiguard`) shows the blast
radius of an API change across a MuleSoft estate: it detects breaking changes in OpenAPI/RAML
specs, maps the *real* dependency network (Exchange + API Manager + Bitbucket/GitHub repo flows &
property files), computes field-level bidirectional blast radius, auto-assigns cross-team
reviewers, and auto-writes changelogs.

## Stack
Java 17 + Spring Boot 3, swagger-parser, PostgreSQL (H2 for tests + dev profile),
Picocli CLI packaged as a GitHub Action, Flutter Web dashboard (graphview + fl_chart),
Slack + GitHub REST integrations.

## Module rules
- `core/` is pure Java (no Spring, no HTTP). CLI and server both depend on it.
- Every diff rule MUST have a unit test with a minimal before/after spec pair.
- Classification enum: BREAKING | NON_BREAKING | ADDITIVE.
- Respect request/response enum asymmetry: widening what the server *accepts*
  (request) is safe; widening what it *returns* (response) can break strict
  consumers; narrowing either side is breaking. Encoded in `core/.../diff/DiffEngine.java`.

## Build order
Phase 1 (core + CLI + Action) is complete. Phase 2 (server + resolver + dashboard) is complete.

## Commands
- Build + test everything:  `./gradlew build`
- Test core only:           `./gradlew :core:test`
- Build CLI fat jar:        `./gradlew :cli:shadowJar`  → `cli/build/libs/apiguard.jar`
- Run CLI:                  `java -jar cli/build/libs/apiguard.jar diff <old> <new> --changelog`
- Run server (no infra):    `./gradlew :server:bootRun --args='--spring.profiles.active=dev'`
- Dashboard (dev):          `cd dashboard && flutter run -d chrome`
- Everything in Docker:     `docker compose -f deploy/docker-compose.yml up --build`

## Layout
- `core/`      diff engine, changelog, blast-radius resolver, manifest model (pure Java)
- `cli/`       `apiguard diff` + `apiguard check`
- `server/`    Spring Boot: REST API, persistence (Flyway), webhook, Slack/GitHub notifiers
- `action/`    composite GitHub Action (`action.yml` + `entrypoint.sh`)
- `dashboard/` Flutter Web app
- `deploy/`    docker-compose + .env.example
- `samples/`   sample specs + manifests used by demos and the seeder
