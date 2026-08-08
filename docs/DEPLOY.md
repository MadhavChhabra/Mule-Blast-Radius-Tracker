# Deploying BlipRadius for end users to test

BlipRadius ships as **one self-contained app**: the server also serves the dashboard, so a tester
opens a single URL and everything works. There are three ways to hand it to people, from
easiest-for-the-tester to most-scalable.

| Path | Best for | Needs installed | Data lives in |
|---|---|---|---|
| **A. Windows desktop app** | non-technical MuleSoft devs on Windows | nothing (bundled JRE) | `~/.apiguard` |
| **B. Docker Compose** | a shared team instance | Docker | a Postgres volume |
| **C. Runnable jar** | anyone with Java 17 | Java 17 | `~/.apiguard` |

The dashboard is always built the same way first (any UI change must be rebuilt):

```bash
cd dashboard && flutter build web --release && cd ..
```

That output is bundled into the server jar automatically, so one process serves both.

---

## A. Windows desktop app (recommended for testers)

Produces a portable folder with `BlipRadius.exe` and a bundled Java runtime — **the tester needs
nothing installed**. They double-click, it opens the dashboard in their browser, and their estate +
saved Anypoint connection persist under `~/.apiguard` across restarts.

**You build it once:**

```bash
cd dashboard && flutter build web --release && cd ..
./gradlew :server:desktopApp        # portable app-image → server/build/desktop/
# optional native installer (.msi needs the WiX Toolset):
./gradlew :server:desktopInstaller
```

Zip the `server/build/desktop/BlipRadius` folder and send it. **The tester:** unzip → run
`BlipRadius.exe` → the browser opens on the dashboard → the first-run wizard walks them through
connecting Anypoint and/or a repo → **Sync everything**.

What persists on their machine (no re-entry on the next launch):
- their estate, changelogs, and scanned/analyzed specs — file database at `~/.apiguard/db`
- their Anypoint connection — client secret **encrypted at rest** with a key auto-created at
  `~/.apiguard/credential.key` (see "Credentials & security" below).

## B. Docker Compose (a shared instance)

The image builds the Flutter dashboard and bundles it into the server jar, so **one container serves
both** the UI and the API on the same origin. Nothing else needs to be published.

```bash
cp deploy/.env.example deploy/.env
# In deploy/.env set APIGUARD_API_KEY_SERVER and a stable APIGUARD_ENCRYPTION_KEY (see below).
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up --build
# BlipRadius → http://localhost:8080
```

Estate data lives in the `apiguard-pg` Postgres volume (survives restarts). For the **saved Anypoint
connection to also survive**, you must set `APIGUARD_ENCRYPTION_KEY` in `.env` (the container has no
persistent home dir for an auto-key). Generate one with `openssl rand -base64 32`, keep it stable,
and back it up.

Set `APIGUARD_API_KEY_SERVER` in `.env` so only your team can call the instance — without it, anyone
who can reach port 8080 can read the estate, start syncs, and scrape `/actuator/prometheus`. Testers
paste that key once via the 🔑 button in the dashboard sidebar (stored in their browser).

The compose file also sets `APIGUARD_ALLOW_LOCAL_PATHS=false`: a container has no local repos worth
scanning, and leaving it on would let a registered "repo" read arbitrary container directories.
Postgres is not published to the host — uncomment its `ports:` block if you need to inspect the DB.

The container runs as a non-root user, carries a `HEALTHCHECK` against `/api/health`, and ships
`git` (required for cloning the repos you register).

## C. Runnable jar (anyone with Java 17)

```bash
cd dashboard && flutter build web --release && cd ..
./gradlew :server:bootJar           # → server/build/libs/*.jar
java -jar server/build/libs/apiguard-server.jar --spring.profiles.active=desktop
# opens http://localhost:8080, data + key under ~/.apiguard
```

Good for a quick internal share; same persistence as the desktop app.

---

## Credentials & security (how "connect once" works)

- The Anypoint **client secret is never stored in plaintext.** It is encrypted with AES-GCM
  (`CredentialCipher`) before being written to the database, and it is never sent back to the browser.
- **Desktop / jar:** if you don't set a key, BlipRadius generates one and keeps it at
  `~/.apiguard/credential.key` (owner-only permissions on macOS/Linux). Zero setup — the connection is
  restored automatically on the next launch. Back up that file if you back up the data.
- **Server / Docker:** set `APIGUARD_ENCRYPTION_KEY` yourself and keep it stable. If the key changes,
  the saved secret can't be decrypted and the user simply reconnects Anypoint once (nothing breaks).
- Turn persistence off entirely with `apiguard.anypoint.persist=false` (or `ANYPOINT_PERSIST=false`) —
  then credentials stay in memory only, as before.
- Environment variables (`ANYPOINT_CLIENT_ID`/`_SECRET`, `GITHUB_TOKEN`, `SLACK_WEBHOOK_URL`) still
  work and take precedence over anything saved in the UI.

## What a tester needs from Anypoint

A **Connected App** (acts on its own behalf, client-credentials) with read scopes:
**API Manager: Read** (required) and **Exchange Viewer: Read** (recommended — enables the catalog and
current-spec download). They paste the client id + secret once in Sources.

## Updating a tester's copy

- **Desktop / jar:** send the new build; the database and key file under `~/.apiguard` are kept, so
  their estate and connection carry over. (Schema changes migrate automatically via Flyway.)
- **Docker:** `docker compose ... up --build` again; the Postgres volume and your encryption key are
  reused.

## Health check

`GET /api/health` returns `{status: UP, version, uptimeSeconds, authRequired}` — use it for a
readiness probe or to confirm a tester's instance is live.
