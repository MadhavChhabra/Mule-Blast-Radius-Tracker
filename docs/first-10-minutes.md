# Your first 10 minutes with Wakegraph

This is the shortest path from "I cloned the repo" to "I can see my estate and gate a PR". It assumes:

- Java 17, Flutter (Web enabled), and a POSIX-ish shell.
- One Anypoint client-credential pair (Connected App with **API Manager: Read**, and optionally **Exchange: Read**).
- One Git repo URL (or an org URL) for the Mule apps you want indexed.

There is no external database to install — the desktop profile uses a persistent H2 file at `~/.apiguard`.

---

## Minute 0 — build once

```bash
cd dashboard && flutter build web --release
cd .. && ./gradlew :cli:shadowJar :server:bootJar
```

You now have:

- `cli/build/libs/apiguard.jar` — the `wakegraph` CLI
- `server/build/libs/*.jar` — the server; it also serves the dashboard at `/`

## Minute 1 — start the server empty

```bash
./gradlew :server:bootRun --args='--spring.profiles.active=dev'
```

Open [http://localhost:8080](http://localhost:8080). The estate is empty on purpose.

> Want a demo estate first? Add `--apiguard.seed.enabled=true` (or set env `SEED_DEMO=true`).
> The seed builds a 3-layer Mule estate with one breaking edge and one cycle, so every screen has something to show.

## Minute 2 — the first-run wizard

The Home screen shows a 3-step card ("Connect your sources → Sync → Explore"). Click **Get started**.

1. **Anypoint** — paste your Connected App `client_id` / `client_secret`, pick your control-plane region.
2. **Repos** — paste one GitHub or Bitbucket URL. It can be a single repo (`.../org/repo`) or an org (`.../org`) — Wakegraph expands orgs to all their repos.
3. **Sync everything** — you'll see a progress bar with a *Cancel* button. On a real 100-app org the first sync is ~2 minutes.

When it finishes, Home shows: how many APIs, how many breaking edges (from any known analyzes), the top depended-on APIs, and any governance findings (upward calls, cycles, layer skips).

## Minute 4 — the Estate map

Nav → **Estate map**. This is one node per API/app, laid out App → Experience → Process → System → Backend. Edges are consumer → producer, curved, arrowed, coloured by risk.

- **Search** — press Ctrl/Cmd-K, or the search icon in the rail. Search covers API names.
- **Governance overlay** — dashed red = upward call or cycle edge; dashed amber = layer skip.
- Click any node → **Open in API hub** to drill in.

## Minute 6 — the API hub

Four tabs per API:

- **Endpoints** — real endpoints from your specs, with per-endpoint downstream and upstream.
- **Change impact** — the two workflows below.
- **Consumers & blast radius** — the graph edges filtered to this API.
- **Spec & history** — every recorded change and version.

### Change impact — the two workflows

1. **Field impact** (before you touch a spec): paste one spec, pick a field, see who carries that field through the estate.
2. **Version diff** (you already have old/new specs): upload both, get the classified diff, the risk score, the recommended semver bump, and a Markdown changelog.

## Minute 8 — enroll one repo for CI

In the repo whose spec you own:

```bash
java -jar path/to/apiguard.jar init \
    --api orders-exp-api \
    --spec src/main/resources/api/orders.raml \
    --server https://wakegraph.yourco.internal
```

This writes:

- `.wakegraph.yml` — the project config (api name, spec path, base branch, server URL, secret name).
- `.github/workflows/wakegraph.yml` (or `bitbucket-pipelines.yml` with `--ci bitbucket`) — a workflow that runs on every PR touching the spec.

Add a repository secret named `WAKEGRAPH_API_KEY` if your server has API-key auth on.

## Minute 9 — see the PR comment

Open a PR that changes your spec. Wakegraph posts one comment with:

- 🟥/🟧/🟨/🟩 risk tile + recommended semver bump.
- The full impact table.
- Per-consumer readiness — the version they were last observed pinned to, when we last saw them, and whether they were discovered only (no explicit manifest committed).
- The Markdown changelog in a collapsed `<details>` block.

## Minute 10 — you're done

You now have:

- An always-current estate map.
- A dependable CI gate that fails only when a breaking change hits a real known consumer.
- A dashboard your platform team can share.

Where to go next:

- Tighten access: set `apiguard.security.api-key` (or env `APIGUARD_API_KEY_SERVER`) and paste the key into the dashboard's key icon.
- Package a desktop `.exe`: `./gradlew :server:desktopApp`.
- Run the whole thing in Docker: `docker compose -f deploy/docker-compose.yml up --build`.
