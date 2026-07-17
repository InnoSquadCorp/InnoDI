#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

ITERATIONS=30
DEFAULT_IN_PROCESS_FILTER="MacroPerformanceBenchmark"
DEFAULT_SUBPROCESS_FILTER="InnoDIMacrosTests"
FILTER=""
BASELINE_FILE="Tools/macro-performance-baseline.json"
REPORT_FILE=""
THRESHOLD_PERCENT=20
UPDATE_BASELINE=0
EXPLICIT_REPORT_ONLY=0
MEASURE_MODE="in-process"
FILTER_OVERRIDE=0
# Honor an externally-set `ENFORCE_REGRESSION_GATE` so callers can opt out of
# the regression gate even inside GitHub Actions (e.g. a workflow that wants
# the timing report without failing the run). Default to enforcing on
# `GITHUB_ACTIONS=true` and to report-only otherwise.
if [[ -z "${ENFORCE_REGRESSION_GATE:-}" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    ENFORCE_REGRESSION_GATE=1
  else
    ENFORCE_REGRESSION_GATE=0
  fi
fi
PERF_LOG="$(mktemp "${TMPDIR:-/tmp}/innodi-macro-perf.XXXXXX")"
IN_PROCESS_REPORT="$(mktemp "${TMPDIR:-/tmp}/innodi-macro-perf-inproc.XXXXXX")"
trap 'rm -f "$PERF_LOG" "$IN_PROCESS_REPORT"' EXIT

usage() {
  cat <<USAGE
Usage: Tools/measure-macro-performance.sh [options]

Options:
  --iterations <N>        Number of measured runs (default: 30)
  --filter <TEST_FILTER>  Swift test filter for --subprocess mode
                          (default: InnoDIMacrosTests)
  --baseline <PATH>       Baseline JSON path (default: Tools/macro-performance-baseline.json)
  --output <PATH>         Write the current measurement JSON to PATH
  --threshold <PCT>       Allowed regression percentage (default: 20)
  --update-baseline       Create or overwrite the baseline with current measurements
  --in-process            Use the in-process SwiftSyntax benchmark (default)
  --subprocess            Measure a full swift test subprocess run
  --enforce               Fail when the threshold is exceeded
  --report-only           Report threshold results without failing
  --help                  Show this help
USAGE
}

require_option_value() {
  local option="$1"
  local current="$2"
  local value="${3:-}"

  if [[ -z "$value" || "$value" == -* ]]; then
    echo "Error: Option $option requires a value (current: $current)" >&2
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --iterations)
      require_option_value "--iterations" "$ITERATIONS" "${2:-}"
      ITERATIONS="$2"
      shift 2
      ;;
    --filter)
      require_option_value "--filter" "$FILTER" "${2:-}"
      FILTER="$2"
      FILTER_OVERRIDE=1
      shift 2
      ;;
    --baseline)
      require_option_value "--baseline" "$BASELINE_FILE" "${2:-}"
      BASELINE_FILE="$2"
      shift 2
      ;;
    --output)
      require_option_value "--output" "$REPORT_FILE" "${2:-}"
      REPORT_FILE="$2"
      shift 2
      ;;
    --threshold)
      require_option_value "--threshold" "$THRESHOLD_PERCENT" "${2:-}"
      THRESHOLD_PERCENT="$2"
      shift 2
      ;;
    --update-baseline)
      UPDATE_BASELINE=1
      shift
      ;;
    --in-process)
      MEASURE_MODE="in-process"
      shift
      ;;
    --subprocess)
      MEASURE_MODE="subprocess"
      shift
      ;;
    --enforce)
      ENFORCE_REGRESSION_GATE=1
      shift
      ;;
    --report-only)
      ENFORCE_REGRESSION_GATE=0
      EXPLICIT_REPORT_ONLY=1
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

if [[ -z "$FILTER" ]]; then
  if [[ "$MEASURE_MODE" == "in-process" ]]; then
    FILTER="$DEFAULT_IN_PROCESS_FILTER"
  else
    FILTER="$DEFAULT_SUBPROCESS_FILTER"
  fi
fi

if [[ "$MEASURE_MODE" == "in-process" && "$FILTER_OVERRIDE" -eq 1 ]]; then
  echo "[macro-perf] --filter is only supported with --subprocess" >&2
  echo "[macro-perf] in-process mode always uses '${DEFAULT_IN_PROCESS_FILTER}'" >&2
  exit 1
fi

read_json_string() {
  local key="$1"
  local file="$2"
  local value=""

  if command -v jq >/dev/null 2>&1; then
    value="$(jq -r ".${key} // empty" "$file" 2>/dev/null || true)"
  fi

  if [[ -z "$value" ]]; then
    value="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$file" | head -n 1)"
  fi

  printf '%s\n' "$value"
}

read_json_number() {
  local key="$1"
  local file="$2"
  local value=""

  if command -v jq >/dev/null 2>&1; then
    value="$(jq -r ".${key} // empty" "$file" 2>/dev/null || true)"
  fi

  if [[ -z "$value" ]]; then
    value="$(sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([0-9.][0-9.]*\\).*/\\1/p" "$file" | head -n 1)"
  fi

  printf '%s\n' "$value"
}

is_positive_number() {
  local value="$1"
  [[ "$value" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] \
    && awk -v value="$value" 'BEGIN { exit(value > 0 ? 0 : 1) }'
}

if ! swift_version_output="$(swift --version 2>/dev/null)"; then
  echo "[macro-perf] failed to read the active Swift version" >&2
  exit 1
fi
swift_version="${swift_version_output%%$'\n'*}"
if [[ -z "$swift_version" ]]; then
  echo "[macro-perf] active Swift version is empty" >&2
  exit 1
fi
swift_version_json="${swift_version//\\/\\\\}"
swift_version_json="${swift_version_json//\"/\\\"}"

preflight_baseline_compatibility() {
  if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
    return 0
  fi

  if [[ ! -f "$BASELINE_FILE" ]]; then
    echo "[macro-perf] baseline missing: $BASELINE_FILE" >&2
    echo "[macro-perf] create it explicitly with --update-baseline" >&2
    exit 1
  fi

  if ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$BASELINE_FILE"; then
    echo "[macro-perf] baseline is not valid JSON: $BASELINE_FILE" >&2
    exit 1
  fi

  local baseline_mode
  baseline_mode="$(read_json_string mode "$BASELINE_FILE")"
  if [[ -z "$baseline_mode" ]]; then
    echo "[macro-perf] baseline mode missing from $BASELINE_FILE; update baseline with --update-baseline" >&2
    exit 1
  fi

  if [[ "$baseline_mode" != "$MEASURE_MODE" ]]; then
    echo "[macro-perf] baseline mode mismatch; refusing to run incompatible measurement" >&2
    echo "[macro-perf] baseline mode='${baseline_mode}'" >&2
    echo "[macro-perf] current mode='${MEASURE_MODE}'" >&2
    echo "[macro-perf] use a baseline generated with the same measurement mode" >&2
    exit 1
  fi

  local baseline_filter
  baseline_filter="$(read_json_string filter "$BASELINE_FILE")"
  if [[ -z "$baseline_filter" ]]; then
    echo "[macro-perf] baseline filter missing from $BASELINE_FILE; update baseline with --update-baseline" >&2
    exit 1
  fi

  if [[ "$baseline_filter" != "$FILTER" ]]; then
    echo "[macro-perf] baseline filter mismatch; refusing to run incompatible measurement" >&2
    echo "[macro-perf] baseline filter='${baseline_filter}'" >&2
    echo "[macro-perf] current filter='${FILTER}'" >&2
    echo "[macro-perf] use a baseline generated with the same test filter" >&2
    exit 1
  fi

  local baseline_swift_version
  baseline_swift_version="$(read_json_string swift_version "$BASELINE_FILE")"
  if [[ -z "$baseline_swift_version" ]]; then
    echo "[macro-perf] baseline swift_version missing from $BASELINE_FILE; update baseline with --update-baseline" >&2
    exit 1
  fi

  if [[ "$baseline_swift_version" != "$swift_version" ]]; then
    echo "[macro-perf] baseline swift version mismatch; refusing to skip the regression gate" >&2
    echo "[macro-perf] baseline swift='${baseline_swift_version}'" >&2
    echo "[macro-perf] current swift='${swift_version}'" >&2
    echo "[macro-perf] update baseline explicitly with --update-baseline after validating the new toolchain" >&2
    exit 1
  fi

  local baseline_mean
  baseline_mean="$(read_json_number mean_ms "$BASELINE_FILE")"
  if ! is_positive_number "$baseline_mean"; then
    echo "[macro-perf] baseline mean_ms must be a finite positive number in $BASELINE_FILE" >&2
    exit 1
  fi
}

preflight_baseline_compatibility

run_once_ms() {
  local started ended elapsed_ms
  started="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000')"
  if ! swift test --filter "$FILTER" >"$PERF_LOG" 2>&1; then
    echo "[macro-perf] measured subprocess failed; check $PERF_LOG" >&2
    return 1
  fi
  ended="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000')"
  elapsed_ms="$(awk -v s="$started" -v e="$ended" 'BEGIN { printf "%.3f", (e - s) / 1000000.0 }')"
  echo "$elapsed_ms"
}

declare -a samples

if [[ "$MEASURE_MODE" == "in-process" ]]; then
  echo "[macro-perf] mode: in-process (SwiftSyntax direct expansion)"
  INNODI_MACRO_BENCH_ITERATIONS="$ITERATIONS" \
  INNODI_MACRO_BENCH_OUTPUT="$IN_PROCESS_REPORT" \
    swift test --filter "$FILTER" >"$PERF_LOG" 2>&1
  if [[ ! -s "$IN_PROCESS_REPORT" ]]; then
    echo "[macro-perf] in-process benchmark produced no report; check $PERF_LOG" >&2
    exit 1
  fi
  # Parse the JSON report the in-process benchmark just wrote so the rest
  # of the script (baseline diff, exit code gating) can treat it like any
  # other measurement run.
  if ! samples_output="$(
    python3 -c '
import json
import math
import sys

with open(sys.argv[1]) as report_file:
    report = json.load(report_file)
expected = int(sys.argv[2])
samples = report.get("samples_ms")
if report.get("iterations") != expected:
    raise SystemExit("benchmark report iterations do not match the requested count")
if not isinstance(samples, list) or len(samples) != expected:
    raise SystemExit("benchmark report sample count does not match the requested count")
for sample in samples:
    if isinstance(sample, bool) or not isinstance(sample, (int, float)):
        raise SystemExit("benchmark samples must be numbers")
    if not math.isfinite(float(sample)) or float(sample) <= 0:
        raise SystemExit("benchmark samples must be finite positive numbers")
    print(f"{float(sample):.3f}")
' "$IN_PROCESS_REPORT" "$ITERATIONS"
  )"; then
    echo "[macro-perf] failed to parse a valid in-process benchmark report: $IN_PROCESS_REPORT" >&2
    exit 1
  fi
  while IFS= read -r sample; do
    [[ -n "$sample" ]] && samples+=("$sample")
  done <<< "$samples_output"
  for i in "${!samples[@]}"; do
    echo "[macro-perf] run $((i+1))/$ITERATIONS: ${samples[$i]} ms"
  done
else
  echo "[macro-perf] mode: subprocess (swift test process timing)"
  echo "[macro-perf] warmup: swift test --filter $FILTER"
  swift test --filter "$FILTER" >"$PERF_LOG" 2>&1

  for i in $(seq 1 "$ITERATIONS"); do
    ms="$(run_once_ms)"
    samples+=("$ms")
    echo "[macro-perf] run $i/$ITERATIONS: ${ms} ms"
  done
fi

if [[ "${#samples[@]}" -ne "$ITERATIONS" ]]; then
  echo "[macro-perf] expected $ITERATIONS samples, received ${#samples[@]}" >&2
  exit 1
fi
for sample in "${samples[@]}"; do
  if ! is_positive_number "$sample"; then
    echo "[macro-perf] invalid sample '$sample'; samples must be finite positive numbers" >&2
    exit 1
  fi
done

samples_lines="$(printf '%s\n' "${samples[@]}")"
mean_ms="$(printf '%s\n' "$samples_lines" | awk '{sum += $1} END { printf "%.3f", sum / NR }')"
min_ms="$(printf '%s\n' "$samples_lines" | awk 'NR == 1 || $1 < min { min = $1 } END { printf "%.3f", min }')"
max_ms="$(printf '%s\n' "$samples_lines" | awk 'NR == 1 || $1 > max { max = $1 } END { printf "%.3f", max }')"
stdev_ms="$(printf '%s\n' "$samples_lines" | awk -v mean="$mean_ms" '{sum += ($1 - mean)^2} END { if (NR <= 1) { printf "%.3f", 0.0 } else { printf "%.3f", sqrt(sum / (NR - 1)) } }')"

updated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
samples_json="$(printf '%s\n' "${samples[@]}" | awk 'BEGIN { printf "[" } NR > 1 { printf ", " } { printf "%s", $1 } END { printf "]" }')"

report_json="$(cat <<JSON
{
  "updated_at": "${updated_at}",
  "swift_version": "${swift_version_json}",
  "mode": "${MEASURE_MODE}",
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

if [[ -n "$REPORT_FILE" ]]; then
  mkdir -p "$(dirname "$REPORT_FILE")"
  printf '%s\n' "$report_json" > "$REPORT_FILE"
  echo "[macro-perf] report written: $REPORT_FILE"
fi

if [[ "$UPDATE_BASELINE" -eq 1 ]]; then
  mkdir -p "$(dirname "$BASELINE_FILE")"
  printf '%s\n' "$report_json" > "$BASELINE_FILE"
  echo "[macro-perf] baseline updated: $BASELINE_FILE"
  exit 0
fi

baseline_mean="$(read_json_number mean_ms "$BASELINE_FILE")"

if ! is_positive_number "$baseline_mean"; then
  echo "[macro-perf] baseline mean_ms must be a finite positive number in $BASELINE_FILE" >&2
  exit 1
fi

regression_pct="$(awk -v current="$mean_ms" -v baseline="$baseline_mean" 'BEGIN { printf "%.2f", ((current - baseline) / baseline) * 100.0 }')"

echo "[macro-perf] baseline mean=${baseline_mean}ms, current mean=${mean_ms}ms, delta=${regression_pct}%"

is_regression="$(awk -v delta="$regression_pct" -v threshold="$THRESHOLD_PERCENT" 'BEGIN { print (delta > threshold) ? 1 : 0 }')"
if [[ "$is_regression" -eq 1 ]]; then
  if [[ "$ENFORCE_REGRESSION_GATE" -eq 1 ]]; then
    echo "[macro-perf] regression exceeded threshold (${THRESHOLD_PERCENT}%)" >&2
    exit 1
  fi

  if [[ "$EXPLICIT_REPORT_ONLY" -eq 1 ]]; then
    report_only_reason="explicit --report-only flag"
  elif [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
    report_only_reason="not running in GitHub Actions"
  else
    report_only_reason="ENFORCE_REGRESSION_GATE=0"
  fi
  echo "[macro-perf] regression exceeded threshold (${THRESHOLD_PERCENT}%); report-only mode, not failing the run (reason: ${report_only_reason})"
  exit 0
fi

echo "[macro-perf] regression within threshold (${THRESHOLD_PERCENT}%)"
