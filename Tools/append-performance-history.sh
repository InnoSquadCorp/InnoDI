#!/usr/bin/env bash
set -euo pipefail

# Tools/append-performance-history.sh
#
# Appends a single macro-performance measurement to the `perf-history`
# branch. Designed to run from a `main` push workflow; the resulting
# branch becomes a time series that
# `Tools/check-performance-trend.sh` consumes for PR-time trend checks.
#
# History layout:
#   perf-history/history/macro-performance/<UTC date>-<short sha>.json
#   perf-history/history/index.json   (sorted list of file paths + metadata)
#
# Each entry is the same JSON shape `Tools/macro-performance-baseline.json`
# uses, with one extra `commit` field added at append time.
#
# Idempotent: re-running for the same commit overwrites the entry rather
# than appending a duplicate. The script is a no-op locally if HEAD is
# detached or the commit is not yet pushed; in CI the commit must exist
# upstream so the trend script's `git log` can resolve it.
#
# Options:
#   --report PATH  Reuse an existing validated measurement instead of running
#                  the benchmark again.
#
# Required environment:
#   GIT_USER_NAME, GIT_USER_EMAIL  — used for the perf-history commit
#   GITHUB_TOKEN                   — needed to push back to origin in CI

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PERF_BRANCH="perf-history"
HISTORY_DIR="history/macro-performance"
INDEX_FILE="history/index.json"

GIT_USER_NAME="${GIT_USER_NAME:-innodi-bot}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-innodi-bot@users.noreply.github.com}"
SOURCE_REPORT=""

usage() {
    cat <<'EOF'
Usage: Tools/append-performance-history.sh [--report <report.json>]

Without --report the script measures macro performance before appending it.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --report)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "--report requires a path" >&2
                exit 2
            fi
            SOURCE_REPORT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "::error::not inside a git repository" >&2
    exit 1
fi

# 1. Reuse the report produced by the gated macro job when supplied. Manual
#    callers retain the previous isolated-measurement behavior.
TMP_BASELINE=$(mktemp -t innodi-perf-XXXXXXXX.json)
trap 'rm -f "$TMP_BASELINE"' EXIT

if [[ -n "$SOURCE_REPORT" ]]; then
    cp "$SOURCE_REPORT" "$TMP_BASELINE"
    echo "[append-perf] reusing macro performance report: $SOURCE_REPORT"
else
    echo "[append-perf] measuring macro performance ..."
    Tools/measure-macro-performance.sh \
        --baseline "$TMP_BASELINE" \
        --update-baseline
fi

python3 Tools/validate-macro-performance-report.py "$TMP_BASELINE" >/dev/null

current_sha=$(git rev-parse HEAD)
short_sha=$(git rev-parse --short=12 HEAD)
commit_iso=$(git show -s --format=%cI "$current_sha")
date_part=$(echo "$commit_iso" | cut -c1-10)

# 2. Decorate the report with the commit SHA so trend checks can join.
ENRICHED=$(mktemp -t innodi-perf-enriched-XXXXXXXX.json)
trap 'rm -f "$TMP_BASELINE" "$ENRICHED"' EXIT
TMP_BASELINE="$TMP_BASELINE" \
COMMIT_SHA="$current_sha" \
COMMIT_ISO="$commit_iso" \
ENRICHED="$ENRICHED" \
python3 - <<'PY'
import json, os
with open(os.environ["TMP_BASELINE"]) as fh:
    data = json.load(fh)
data["commit"] = os.environ["COMMIT_SHA"]
data["commit_at"] = os.environ["COMMIT_ISO"]
with open(os.environ["ENRICHED"], "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY

# 3. Stash any uncommitted state, switch to perf-history, write the entry,
#    update the index, commit, push, and switch back to the original
#    branch / commit. The orphan-create path covers the first run.

original_ref=$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)

git fetch origin "$PERF_BRANCH" >/dev/null 2>&1 || true

# Save the enriched report outside the work tree before any branch switch,
# because the file lives in /tmp/ but `git checkout` will reset tracked
# changes only.
saved=$(mktemp -t innodi-perf-saved-XXXXXXXX.json)
cp "$ENRICHED" "$saved"
trap 'rm -f "$TMP_BASELINE" "$ENRICHED" "$saved"' EXIT

if git ls-remote --exit-code origin "refs/heads/$PERF_BRANCH" >/dev/null 2>&1; then
    git checkout -B "$PERF_BRANCH" "origin/$PERF_BRANCH"
else
    echo "[append-perf] perf-history branch missing on origin; bootstrapping orphan branch"
    git checkout --orphan "$PERF_BRANCH"
    git rm -rf --cached . >/dev/null 2>&1 || true
    # Wipe the work tree so the orphan branch starts empty.
    find . -mindepth 1 -maxdepth 1 \
        ! -name ".git" \
        -exec rm -rf {} +
    cat > README.md <<EOF
# InnoDI performance history

This branch is an append-only time series for macro-performance
measurements. Entries land here from \`Tools/append-performance-history.sh\`
running on each push to \`main\`. Do not commit application code or
documentation here; \`Tools/check-performance-trend.sh\` reads only the
files under \`history/\`.
EOF
fi

mkdir -p "$HISTORY_DIR"
entry_path="$HISTORY_DIR/${date_part}-${short_sha}.json"
cp "$saved" "$entry_path"

# Rebuild a deterministic index so consumers do not have to walk the
# directory.
ENTRY_PATH="$entry_path" HISTORY_DIR="$HISTORY_DIR" INDEX_FILE="$INDEX_FILE" python3 - <<'PY'
import json, os, glob
history_dir = os.environ["HISTORY_DIR"]
index_file = os.environ["INDEX_FILE"]
entries = []
for path in sorted(glob.glob(os.path.join(history_dir, "*.json"))):
    with open(path) as fh:
        data = json.load(fh)
    entries.append({
        "path": path,
        "commit": data.get("commit"),
        "commit_at": data.get("commit_at"),
        "swift_version": data.get("swift_version"),
        "mode": data.get("mode"),
        "filter": data.get("filter"),
        "iterations": data.get("iterations"),
        "mean_ms": data.get("mean_ms"),
        "median_ms": data.get("median_ms"),
        "min_ms": data.get("min_ms"),
        "max_ms": data.get("max_ms"),
        "stdev_ms": data.get("stdev_ms"),
    })
os.makedirs(os.path.dirname(index_file), exist_ok=True)
with open(index_file, "w") as fh:
    json.dump({"entries": entries}, fh, indent=2)
    fh.write("\n")
PY

git config user.name "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"
git add "$entry_path" "$INDEX_FILE" README.md 2>/dev/null || true
if git diff --cached --quiet; then
    echo "[append-perf] no changes to commit (entry already up to date)"
else
    git commit -m "Append macro-perf entry for ${short_sha}" >/dev/null
    git push origin "$PERF_BRANCH"
fi

# 4. Restore the caller's checkout. `original_ref` is either a branch name
#    or a detached commit SHA; both work with `git checkout`.
git checkout "$original_ref"

echo "[append-perf] appended ${entry_path} on ${PERF_BRANCH}"
