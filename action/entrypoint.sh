#!/usr/bin/env bash
set -euo pipefail

ACTION_DIR="${ACTION_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
REPO_DIR="$(cd "$ACTION_DIR/.." && pwd)"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

JAR=""
for cand in "/app/apiguard.jar" "$REPO_DIR/cli/build/libs/apiguard.jar"; do
  if [ -f "$cand" ]; then JAR="$cand"; break; fi
done
if [ -z "$JAR" ]; then
  echo "Building Wakegraph CLI..."
  (cd "$REPO_DIR" && ./gradlew :cli:shadowJar --no-daemon -q)
  JAR="$REPO_DIR/cli/build/libs/apiguard.jar"
fi

OLD="$INPUT_OLD_SPEC"
NEW="$INPUT_NEW_SPEC"
API="${INPUT_API:-}"
MANIFESTS="${INPUT_MANIFESTS:-.}"
FAIL="${INPUT_FAIL_ON_BREAKING:-true}"
SERVER="${INPUT_SERVER:-}"

cd "$WORKSPACE"

MD_REPORT=""
set +e
if [ -n "$SERVER" ] && [ -n "$API" ]; then
  MD_REPORT="$(mktemp)"
  REPORT="$(java -jar "$JAR" impact "$OLD" "$NEW" --api "$API" --server "$SERVER" \
      --markdown "$MD_REPORT" --no-color)"
elif [ -n "$API" ]; then
  REPORT="$(java -jar "$JAR" check "$OLD" "$NEW" --api "$API" --manifests "$MANIFESTS" --no-color)"
else
  REPORT="$(java -jar "$JAR" diff "$OLD" "$NEW" --fail-on-breaking --no-color)"
fi
CODE=$?
set -e
echo "$REPORT"

CHANGELOG="$(java -jar "$JAR" diff "$OLD" "$NEW" --changelog --no-color || true)"

BREAKING_COUNT="$(printf '%s\n' "$REPORT" | grep -c '^BREAKING' || true)"
echo "breaking-count=${BREAKING_COUNT:-0}" >> "${GITHUB_OUTPUT:-/dev/null}"

if [ "${INPUT_COMMENT:-true}" = "true" ] && [ -n "${INPUT_GITHUB_TOKEN:-}" ] \
    && [ -f "${GITHUB_EVENT_PATH:-/dev/null}" ]; then
  PR="$(jq -r '.pull_request.number // empty' "$GITHUB_EVENT_PATH")"
  if [ -n "$PR" ]; then
    if [ -n "$MD_REPORT" ] && [ -s "$MD_REPORT" ]; then
      BODY_MD="$(cat "$MD_REPORT")"
    else
      BODY_MD="$(printf '## 🛡️ Wakegraph report\n\n```\n%s\n```\n\n%s\n' "$REPORT" "$CHANGELOG")"
    fi
    BODY_JSON="$(jq -Rs '{body: .}' <<< "$BODY_MD")"
    curl -sS -X POST \
      -H "Authorization: Bearer $INPUT_GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      "${GITHUB_API_URL:-https://api.github.com}/repos/${GITHUB_REPOSITORY}/issues/${PR}/comments" \
      -d "$BODY_JSON" > /dev/null && echo "Posted PR comment to #$PR"
  fi
fi

if [ "$FAIL" = "true" ] && [ "$CODE" -ne 0 ]; then
  echo "Wakegraph: breaking changes detected -> failing the check."
  exit 1
fi
echo "Wakegraph: no blocking changes."
