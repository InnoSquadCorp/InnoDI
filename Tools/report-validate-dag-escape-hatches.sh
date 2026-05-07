#!/usr/bin/env bash
set -euo pipefail

# Tools/report-validate-dag-escape-hatches.sh
#
# Surfaces every site that uses an InnoDI build-validation escape hatch so
# reviewers can see — at a glance — how many `validateDAG: false` sites a
# PR introduces and whether the build environment is silently disabling
# validation entirely. There are two escape hatches today:
#
# 1. `@DIContainer(validateDAG: false)` — a per-container source-level
#    opt-out. The `@DIContainer` docstring already calls this "a temporary
#    fixture rather than a release-quality flag," but until now nothing
#    counted how often it appeared in any single PR.
#
# 2. `INNODI_DISABLE_BUILD_VALIDATION=1` (read by
#    `Plugins/InnoDIDAGValidationPlugin/plugin.swift`) — an environment-
#    level kill switch that skips the entire build-time DAG gate. CI runs
#    must leave this unset; the script flags it when it is set.
#
# Output:
#   - stdout: a Markdown summary (suitable for $GITHUB_STEP_SUMMARY)
#   - $INNODI_ESCAPE_HATCH_JSON (optional): structured JSON for downstream
#     tooling. Defaults to `build/escape-hatch-report.json` when set.
#
# Detection is grep-based on `validateDAG: false`. That is fast, has zero
# build dependencies, and matches the same literal the parser already
# extracts. Commented-out occurrences are filtered. Production sources and
# fixtures are reported separately so a snapshot or example file counts
# distinctly from a real production opt-out.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PRODUCTION_ROOTS=("Sources" "Plugins")
FIXTURE_ROOTS=("Tests" "Examples")

# grep pattern: same-line `@DIContainer(...validateDAG: false...)`.
# This deliberately ignores multi-line attribute bodies (very rare in
# this codebase) so that string literals such as
# `"DAG validation passed (validateDAG: false)"` and ordinary function
# arguments such as `collectRenderableDependencyGraph(snapshot:, validateDAG: false)`
# do not trip the report. Lines that begin (after optional whitespace)
# with `//` are filtered as obvious comments.
PATTERN='@DIContainer.*validateDAG[[:space:]]*:[[:space:]]*false'

scan_root() {
    local root="$1"
    if [[ ! -d "$root" ]]; then
        return 0
    fi
    grep -rnE "$PATTERN" "$root" \
        --include='*.swift' \
        --exclude-dir='.build' \
        --exclude-dir='__Snapshots__' \
        2>/dev/null \
        | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
        || true
}

PRODUCTION_HITS=""
for root in "${PRODUCTION_ROOTS[@]}"; do
    hits=$(scan_root "$root")
    if [[ -n "$hits" ]]; then
        PRODUCTION_HITS="${PRODUCTION_HITS}${hits}"$'\n'
    fi
done

FIXTURE_HITS=""
for root in "${FIXTURE_ROOTS[@]}"; do
    hits=$(scan_root "$root")
    if [[ -n "$hits" ]]; then
        FIXTURE_HITS="${FIXTURE_HITS}${hits}"$'\n'
    fi
done

production_count=$(printf '%s' "$PRODUCTION_HITS" | grep -cE '.' || true)
fixture_count=$(printf '%s' "$FIXTURE_HITS" | grep -cE '.' || true)

env_disabled="false"
env_disabled_value="${INNODI_DISABLE_BUILD_VALIDATION:-}"
case "${env_disabled_value,,}" in
    1|true|yes) env_disabled="true";;
esac

# ---- Markdown report (stdout) ----

echo "### InnoDI build-validation escape hatches"
echo
if [[ "$env_disabled" == "true" ]]; then
    echo ":rotating_light: \`INNODI_DISABLE_BUILD_VALIDATION=${env_disabled_value}\` is set in this build environment. The DAG validation plugin will return zero build commands and the gate will not run. Production CI must leave this variable unset."
    echo
fi

echo "**Production opt-outs (\`Sources/\`, \`Plugins/\`):** ${production_count}  "
echo "**Fixture opt-outs (\`Tests/\`, \`Examples/\`):** ${fixture_count}"
echo

if [[ "$production_count" -gt 0 ]]; then
    echo "<details><summary>Production sites</summary>"
    echo
    echo '```'
    printf '%s' "$PRODUCTION_HITS"
    echo '```'
    echo
    echo "</details>"
    echo
fi

if [[ "$fixture_count" -gt 0 ]]; then
    echo "<details><summary>Fixture sites (tests / examples)</summary>"
    echo
    echo '```'
    printf '%s' "$FIXTURE_HITS"
    echo '```'
    echo
    echo "</details>"
    echo
fi

echo "_Detection is grep-based; commented-out lines are filtered. \`validateDAG: false\` is documented as a narrow temporary fixture in \`@DIContainer\`'s docstring; \`INNODI_DISABLE_BUILD_VALIDATION\` is documented in \`README.md\` and \`Plugins/InnoDIDAGValidationPlugin/plugin.swift\`._"

# ---- Optional JSON output ----

JSON_OUT="${INNODI_ESCAPE_HATCH_JSON:-}"
if [[ -n "$JSON_OUT" ]]; then
    mkdir -p "$(dirname "$JSON_OUT")"
    INNODI_PRODUCTION_HITS="$PRODUCTION_HITS" \
    INNODI_FIXTURE_HITS="$FIXTURE_HITS" \
    INNODI_ENV_DISABLED="$env_disabled" \
    INNODI_ENV_VALUE="$env_disabled_value" \
    INNODI_JSON_OUT="$JSON_OUT" \
    python3 - <<'PY'
import json, os, re

def parse(blob: str):
    out = []
    for line in blob.splitlines():
        if not line.strip():
            continue
        m = re.match(r"^([^:]+):(\d+):(.*)$", line)
        if not m:
            continue
        out.append({
            "file": m.group(1),
            "line": int(m.group(2)),
            "snippet": m.group(3).strip(),
        })
    return out

production = parse(os.environ.get("INNODI_PRODUCTION_HITS", ""))
fixtures = parse(os.environ.get("INNODI_FIXTURE_HITS", ""))

result = {
    "validateDAGFalse": {
        "production": production,
        "fixtures": fixtures,
        "productionCount": len(production),
        "fixtureCount": len(fixtures),
    },
    "envDisabled": os.environ["INNODI_ENV_DISABLED"] == "true",
    "envDisabledValue": os.environ.get("INNODI_ENV_VALUE", ""),
}

with open(os.environ["INNODI_JSON_OUT"], "w") as fh:
    json.dump(result, fh, indent=2)
    fh.write("\n")
PY
fi

# Exit code: 0 by default (informational). Set INNODI_ESCAPE_HATCH_FAIL=1
# to make a non-zero production count fail the build (useful for orgs that
# treat any new opt-out as a release blocker).
if [[ "${INNODI_ESCAPE_HATCH_FAIL:-0}" == "1" && "$production_count" -gt 0 ]]; then
    echo "::error::INNODI_ESCAPE_HATCH_FAIL=1 and ${production_count} production opt-out(s) detected" >&2
    exit 1
fi

if [[ "${INNODI_ESCAPE_HATCH_FAIL:-0}" == "1" && "$env_disabled" == "true" ]]; then
    echo "::error::INNODI_ESCAPE_HATCH_FAIL=1 and INNODI_DISABLE_BUILD_VALIDATION is set" >&2
    exit 1
fi

exit 0
