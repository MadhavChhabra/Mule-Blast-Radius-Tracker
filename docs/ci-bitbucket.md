# Wakegraph on Bitbucket Pipelines

`wakegraph init --ci bitbucket` writes a `bitbucket-pipelines.yml` that runs the impact command on every PR touching your spec and fails the build when a breaking change hits a real known consumer.

This walkthrough covers the two Repository variables you need to set once.

## 1. Enable Pipelines

Repository → **Repository settings → Pipelines → Settings** → toggle *Enable Pipelines*.

## 2. Add two Repository variables

Repository → **Repository settings → Repository variables** and add:

| Name | Value | Secured |
|---|---|---|
| `WAKEGRAPH_SERVER` | your Wakegraph URL, e.g. `https://wakegraph.internal` | no |
| `WAKEGRAPH_API_KEY` | matches the server's `apiguard.security.api-key` (leave off if the server has no auth) | **yes** |

The generated `bitbucket-pipelines.yml` reads both. The API key is exported into `APIGUARD_API_KEY` so the CLI picks it up like it does in every other environment.

## 3. Commit the two generated files

- `.wakegraph.yml` — project config (api name, spec path, base branch, server, secret name)
- `bitbucket-pipelines.yml` — the pipeline

Push a PR that changes your spec. The Wakegraph step:

- fetches the destination branch (using `$BITBUCKET_PR_DESTINATION_BRANCH`, falling back to the base you passed to `init`)
- runs `wakegraph impact <spec> --base "$BASE" --api <name> --server "$WAKEGRAPH_SERVER"`
- writes `wakegraph-report.md` as a step artifact you can open from the pipeline result
- exits `1` when a breaking change hits a real known consumer (change with `--fail-on breaking` or `never`)

## 4. Optional — turn the artifact into a PR comment

Bitbucket doesn't have a first-class "post PR comment from pipeline" primitive, so pipe the artifact through their REST API:

```yaml
      - step:
          name: Post Wakegraph report as a PR comment
          script:
            - |
              curl -X POST -u "$BITBUCKET_USER:$BITBUCKET_APP_PASSWORD" \
                -H "Content-Type: application/json" \
                "https://api.bitbucket.org/2.0/repositories/${BITBUCKET_REPO_FULL_NAME}/pullrequests/${BITBUCKET_PR_ID}/comments" \
                -d "$(jq -Rs '{content:{raw:.}}' < wakegraph-report.md)"
```

Two extra repository variables: `BITBUCKET_USER` and `BITBUCKET_APP_PASSWORD` (an [App password](https://bitbucket.org/account/settings/app-passwords/) with **Pull requests: Write**).

## Troubleshooting

- **The impact step fails with `Could not reach Wakegraph`** — check `WAKEGRAPH_SERVER` is reachable from Bitbucket Pipelines runners (public URL or a self-hosted runner in your VPC).
- **The step passes even on a breaking change** — the CLI only fails on `breaking-impact` (breaking change that hits a *real* known consumer). If you want to gate any breaking change regardless of consumers, edit the generated file to use `--fail-on breaking`.
- **`git fetch` fails with `unknown revision`** — the pipeline's `clone.depth: full` fetches the whole history; the extra `git fetch --depth=100 origin <base>` is a safety net when `full` isn't honored. Increase depth if your base has been rebased far back.
