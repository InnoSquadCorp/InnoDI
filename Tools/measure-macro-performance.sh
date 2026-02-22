#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ITERATIONS=5
FILTER="InnoDIMacrosTests"
BASELINE_FILE="Tools/macro-performance-baseline.json"
THRESHOLD_PERCENT=20
UPDATE_BASELINE=0

usage() {
  cat <<USAGE
Usage: Tools/measure-macro-performance.sh [options]

Options:
  --iterations <N>        Number of measured runs (default: 5)
  --filter <TEST_FILTER>  Swift test filter (default: InnoDIMacrosTests)
  --baseline <PATH>       Baseline JSON path (default: Tools/macro-performance-baseline.json)
  --threshold <PCT>       Allowed regression percentage (default: 20)
  --update-baseline       Overwrite baseline with current measurements
  --help                  Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iterations)
      ITERATIONS="$2"
      shift 2
      ;;
    --filter)
      FILTER="$2"
      shift 2
      ;;
    --baseline)
      BASELINE_FILE="$2"
      shift 2
      ;;
    --threshold)
      THRESHOLD_PERCENT="$2"
      shift 2
      ;;
    --update-baseline)
      UPDATE_BASELINE=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if ! [[ "$ITERATIONS" =~ ^[0-9]+$ ]] || [[ "$ITERATIONS" -lt 1 ]]; then
  echo "--iterations must be a positive integer" >&2
  exit 1
fi

if ! [[ "$THRESHOLD_PERCENT" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "--threshold must be a number" >&2
  exit 1
fi

run_once_ms() {
  local started ended elapsed_ms
  started="$(date +%s%N)"
  swift test --filter "$FILTER" >/tmp/innodi-macro-perf.log 2>&1
  ended="$(date +%s%N)"
  elapsed_ms="$(awk -v s="$started" -v e="$ended" 'BEGIN { printf "%.3f", (e - s) / 1000000.0 }')"
  echo "$elapsed_ms"
}

echo "[macro-perf] warmup: swift test --filter $FILTER"
swift test --filter "$FILTER" >/tmp/innodi-macro-perf.log 2>&1

declare -a samples
for i in $(seq 1 "$ITERATIONS"); do
  ms="$(run_once_ms)"
  samples+=("$ms")
  echo "[macro-perf] run $i/$ITERATIONS: ${ms} ms"
done

samples_lines="$(printf '%s\n' "${samples[@]}")"
mean_ms="$(printf '%s\n' "$samples_lines" | awk '{sum += $1} END { printf "%.3f", sum / NR }')"
min_ms="$(printf '%s\n' "$samples_lines" | awk 'NR == 1 || $1 < min { min = $1 } END { printf "%.3f", min }')"
max_ms="$(printf '%s\n' "$samples_lines" | awk 'NR == 1 || $1 > max { max = $1 } END { printf "%.3f", max }')"
stdev_ms="$(printf '%s\n' "$samples_lines" | awk -v mean="$mean_ms" '{sum += ($1 - mean)^2} END { printf "%.3f", sqrt(sum / NR) }')"

swift_version="$(swift --version 2>/dev/null | head -n 1 | sed 's/"/\\"/g')"
updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
samples_json="$(printf '%s\n' "${samples[@]}" | awk 'BEGIN { printf "[" } NR > 1 { printf ", " } { printf "%s", $1 } END { printf "]" }')"

report_json="$(cat <<JSON
{
  "updated_at": "${updated_at}",
  "swift_version": "${swift_version}",
  "filter": "${FILTER}",
  "iterations": ${ITERATIONS},
  "mean_ms": ${mean_ms},
  "min_ms": ${min_ms},
  "max_ms": ${max_ms},
  "stdev_ms": ${stdev_ms},
  "samples_ms": ${samples_json}
}
JSON
)"

echo "[macro-perf] summary: mean=${mean_ms}ms min=${min_ms}ms max=${max_ms}ms stdev=${stdev_ms}ms"

mkdir -p "$(dirname "$BASELINE_FILE")"

if [[ "$UPDATE_BASELINE" -eq 1 || ! -f "$BASELINE_FILE" ]]; then
  printf '%s\n' "$report_json" > "$BASELINE_FILE"
  echo "[macro-perf] baseline updated: $BASELINE_FILE"
  exit 0
fi

baseline_mean="$(sed -n 's/.*"mean_ms"[[:space:]]*:[[:space:]]*\([0-9.][0-9.]*\).*/\1/p' "$BASELINE_FILE" | head -n 1)"
if [[ -z "$baseline_mean" ]]; then
  echo "[macro-perf] failed to parse baseline mean_ms from $BASELINE_FILE" >&2
  exit 1
fi

regression_pct="$(awk -v current="$mean_ms" -v baseline="$baseline_mean" 'BEGIN { if (baseline == 0) { print "0.00" } else { printf "%.2f", ((current - baseline) / baseline) * 100.0 } }')"

echo "[macro-perf] baseline mean=${baseline_mean}ms, current mean=${mean_ms}ms, delta=${regression_pct}%"

is_regression="$(awk -v delta="$regression_pct" -v threshold="$THRESHOLD_PERCENT" 'BEGIN { print (delta > threshold) ? 1 : 0 }')"
if [[ "$is_regression" -eq 1 ]]; then
  echo "[macro-perf] regression exceeded threshold (${THRESHOLD_PERCENT}%)" >&2
  exit 1
fi

echo "[macro-perf] regression within threshold (${THRESHOLD_PERCENT}%)"
