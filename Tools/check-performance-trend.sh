#!/usr/bin/env bash
set -euo pipefail

# Tools/check-performance-trend.sh
#
# Compares the current macro-performance measurement against the rolling
# median of the last N entries on the `perf-history` branch.
#
# Why this exists alongside `Tools/measure-macro-performance.sh --enforce`:
# the existing enforcement compares against a single pinned baseline JSON
# in `Tools/macro-performance-baseline.json`. That catches large
# regressions but misses gradual creep — a series of small,
# under-threshold regressions can still add up across a quarter without
# any single PR breaking the gate. This script reads the time series
# `Tools/append-performance-history.sh` writes to the `perf-history`
# branch and compares the current run against the rolling median.
#
# Behaviour:
#   - If `perf-history` is empty or unreachable, exits 0 silently. That
#     covers fresh forks, first-time setups, and PRs from contributors
#     who cannot fetch the branch (e.g. minimum-permission runs).
#   - If history has fewer than $MIN_SAMPLES entries (default 5), exits
#     0 with an informational note; the trend signal is too weak yet.
#   - Otherwise computes the rolling median of the last $WINDOW entries'
#     per-run min_ms and compares the current lower envelope. This avoids
#     treating shared-runner scheduling delays as product regressions while a
#     real slowdown still raises every valid sample. Regression above
#     $THRESHOLD_PCT fails the script.
#
# Environment:
#   INNODI_TREND_WINDOW         (default: 7)   trailing entries to consider
#   INNODI_TREND_THRESHOLD_PCT  (default: 20)  fail above this
#   INNODI_TREND_MIN_SAMPLES    (default: 5)   below this just report
#   INNODI_TREND_REQUIRE_SAME_TOOLCHAIN (default: 1)
#       When 1, history entries with a different swift_version than the
#       current run are ignored — keeps the trend honest across
#       toolchain bumps without requiring history reset.

usage() {
    cat <<'EOF'
Usage: Tools/check-performance-trend.sh [--current-report <report.json>]

Without --current-report the script measures macro performance itself.
Pass the report emitted by measure-macro-performance.sh --output to reuse an
already enforced measurement.
EOF
}

CURRENT_REPORT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --current-report)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "--current-report requires a path" >&2
                exit 2
            fi
            CURRENT_REPORT="$2"
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

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PERF_BRANCH="perf-history"
WINDOW="${INNODI_TREND_WINDOW:-7}"
THRESHOLD_PCT="${INNODI_TREND_THRESHOLD_PCT:-20}"
MIN_SAMPLES="${INNODI_TREND_MIN_SAMPLES:-5}"
REQUIRE_SAME_TOOLCHAIN="${INNODI_TREND_REQUIRE_SAME_TOOLCHAIN:-1}"

# 1. Reuse an enforced report when supplied. Standalone callers retain the
#    previous behavior and run a fresh measurement into a temporary file.
TMP_BASELINE=$(mktemp -t innodi-perf-trend-XXXXXXXX.json)
trap 'rm -f "$TMP_BASELINE"' EXIT

if [[ -n "$CURRENT_REPORT" ]]; then
    cp "$CURRENT_REPORT" "$TMP_BASELINE"
    echo "[trend] reusing macro performance report: $CURRENT_REPORT"
else
    echo "[trend] measuring macro performance for trend comparison ..."
    Tools/measure-macro-performance.sh \
        --baseline "$TMP_BASELINE" \
        --update-baseline >/dev/null
fi

python3 Tools/validate-macro-performance-report.py "$TMP_BASELINE" >/dev/null

# 2. Try to fetch perf-history. Treat any failure as "no history yet" and
#    short-circuit with a friendly message.
if ! git fetch origin "$PERF_BRANCH" 2>/dev/null; then
    echo "[trend] perf-history branch unreachable; skipping trend check"
    exit 0
fi

if ! git rev-parse --quiet --verify "origin/$PERF_BRANCH" >/dev/null; then
    echo "[trend] no perf-history branch yet; skipping trend check"
    exit 0
fi

INDEX_BLOB=$(git show "origin/${PERF_BRANCH}:history/index.json" 2>/dev/null || true)
if [[ -z "$INDEX_BLOB" ]]; then
    echo "[trend] perf-history has no index.json yet; skipping trend check"
    exit 0
fi

# 3. Compute the rolling median in python (jq not guaranteed on macOS
#    runners). Filter by toolchain when requested.
TREND_OUT=$(mktemp -t innodi-trend-XXXXXXXX.json)
trap 'rm -f "$TMP_BASELINE" "$TREND_OUT"' EXIT

INNODI_TREND_INDEX="$INDEX_BLOB" \
INNODI_TREND_CURRENT="$TMP_BASELINE" \
INNODI_TREND_WINDOW="$WINDOW" \
INNODI_TREND_THRESHOLD_PCT="$THRESHOLD_PCT" \
INNODI_TREND_MIN_SAMPLES="$MIN_SAMPLES" \
INNODI_TREND_REQUIRE_SAME_TOOLCHAIN="$REQUIRE_SAME_TOOLCHAIN" \
INNODI_TREND_OUT="$TREND_OUT" \
python3 - <<'PY'
import json, os, sys

index = json.loads(os.environ["INNODI_TREND_INDEX"])
with open(os.environ["INNODI_TREND_CURRENT"]) as fh:
    current = json.load(fh)
window = int(os.environ["INNODI_TREND_WINDOW"])
threshold_pct = float(os.environ["INNODI_TREND_THRESHOLD_PCT"])
min_samples = int(os.environ["INNODI_TREND_MIN_SAMPLES"])
require_same = os.environ["INNODI_TREND_REQUIRE_SAME_TOOLCHAIN"] == "1"

entries = index.get("entries", [])
if require_same and current.get("swift_version"):
    entries = [e for e in entries if e.get("swift_version") == current["swift_version"]]

def comparison_ms(entry):
    value = entry.get("min_ms")
    if isinstance(value, bool) or not isinstance(value, (int, float)) or value <= 0:
        return None
    return float(value)

# index.json is sorted by commit_at (with path as a deterministic tie-breaker),
# so the last N comparable entries are the most recent. Filter out entries with
# mode/filter mismatches in case a future change splits the time series.
entries = [
    e for e in entries
    if e.get("mode") == current.get("mode")
       and e.get("filter") == current.get("filter")
       and comparison_ms(e) is not None
]
recent = entries[-window:]

current_min = current["min_ms"]
report = {
    "metric": "min_ms",
    "currentMinMs": current_min,
    "currentMedianMs": current.get("median_ms"),
    "currentMeanMs": current.get("mean_ms"),
    "considered": len(entries),
    "windowUsed": len(recent),
    "windowConfigured": window,
    "thresholdPct": threshold_pct,
    "minSamples": min_samples,
    "requireSameToolchain": require_same,
    "samples": [
        {
            "commit": e.get("commit"),
            "min_ms": e.get("min_ms"),
            "median_ms": e.get("median_ms"),
            "mean_ms": e.get("mean_ms"),
            "comparison_ms": comparison_ms(e),
        }
        for e in recent
    ],
}

if len(recent) < min_samples:
    report["status"] = "insufficient-history"
    report["note"] = f"only {len(recent)} comparable entries (need {min_samples})"
    with open(os.environ["INNODI_TREND_OUT"], "w") as fh:
        json.dump(report, fh, indent=2)
    print(f"[trend] {report['note']} — skipping comparison")
    sys.exit(0)

centers = sorted(comparison_ms(e) for e in recent)
mid = len(centers) // 2
rolling_median = centers[mid] if len(centers) % 2 == 1 else (centers[mid - 1] + centers[mid]) / 2.0

regression_pct = ((current_min - rolling_median) / rolling_median) * 100.0
report["rollingMedianOfMinMs"] = rolling_median
report["regressionPct"] = round(regression_pct, 2)

if regression_pct > threshold_pct:
    report["status"] = "regression"
else:
    report["status"] = "ok"

with open(os.environ["INNODI_TREND_OUT"], "w") as fh:
    json.dump(report, fh, indent=2)

print(f"[trend] current min={current_min:.3f}ms rolling median of min(last {len(recent)})={rolling_median:.3f}ms "
      f"delta={regression_pct:+.2f}% threshold={threshold_pct:.2f}%")

if report["status"] == "regression":
    print(f"::error::macro-perf trend regression: {regression_pct:+.2f}% above rolling median ({threshold_pct:.2f}% threshold)")
    sys.exit(1)
PY

# Surface the JSON report so the workflow can upload it as an artifact.
mkdir -p build
cp "$TREND_OUT" build/perf-trend-report.json
echo "[trend] report saved to build/perf-trend-report.json"
