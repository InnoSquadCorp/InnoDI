#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILE_RESULT="$ROOT_DIR/Benchmarks/results/compile.json"
RUNTIME_RESULT="$ROOT_DIR/Benchmarks/results/runtime.json"
VALIDATION_RESULT="$ROOT_DIR/Benchmarks/results/validation.json"
COMPARE_RESULT="$ROOT_DIR/Benchmarks/results/compare.json"
VALIDATION_COMPARE_RESULT="$ROOT_DIR/Benchmarks/results/validation-compare.json"
VALIDATION_COMPARE_SUMMARY="$ROOT_DIR/Benchmarks/results/validation-compare.md"
VALIDATION_BASELINE="$ROOT_DIR/Benchmarks/validation-performance-baseline.json"

PRESET="local"
COMPILE_ITERATIONS=5
RUNTIME_RUNS=5
RUNTIME_ITERATIONS=100000
VALIDATION_RUNS=3
VALIDATION_THRESHOLD_PERCENT=20
UPDATE_VALIDATION_BASELINE=0
SIZES_CSV=""

COMPILE_ITERATIONS_EXPLICIT=0
RUNTIME_RUNS_EXPLICIT=0
RUNTIME_ITERATIONS_EXPLICIT=0
VALIDATION_RUNS_EXPLICIT=0
SIZES_EXPLICIT=0

usage() {
  cat <<USAGE
Usage: Benchmarks/compare.sh [options]

Options:
  --preset <local|ci>            Benchmark preset (default: local)
  --compile-iterations <N>       Compile benchmark iterations
  --runtime-runs <N>             Runtime benchmark sample runs
  --runtime-iterations <N>       Runtime resolve iterations per sample
  --validation-runs <N>          Validation benchmark sample runs
  --validation-baseline <PATH>   Validation baseline JSON path
  --validation-threshold <PCT>   Allowed validation regression percentage
  --update-validation-baseline   Overwrite validation baseline with current run
  --sizes <CSV>                  Comma-separated scenario sizes
  --output <PATH>                Aggregate comparison output JSON
  --help                         Show this help
USAGE
}

require_option_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    echo "Missing value for $option" >&2
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preset)
      require_option_value "$1" "${2:-}"
      PRESET="${2:-}"
      shift 2
      ;;
    --compile-iterations)
      require_option_value "$1" "${2:-}"
      COMPILE_ITERATIONS="$2"
      COMPILE_ITERATIONS_EXPLICIT=1
      shift 2
      ;;
    --runtime-runs)
      require_option_value "$1" "${2:-}"
      RUNTIME_RUNS="$2"
      RUNTIME_RUNS_EXPLICIT=1
      shift 2
      ;;
    --runtime-iterations)
      require_option_value "$1" "${2:-}"
      RUNTIME_ITERATIONS="$2"
      RUNTIME_ITERATIONS_EXPLICIT=1
      shift 2
      ;;
    --validation-runs)
      require_option_value "$1" "${2:-}"
      VALIDATION_RUNS="$2"
      VALIDATION_RUNS_EXPLICIT=1
      shift 2
      ;;
    --validation-baseline)
      require_option_value "$1" "${2:-}"
      VALIDATION_BASELINE="$2"
      shift 2
      ;;
    --validation-threshold)
      require_option_value "$1" "${2:-}"
      VALIDATION_THRESHOLD_PERCENT="$2"
      shift 2
      ;;
    --update-validation-baseline)
      UPDATE_VALIDATION_BASELINE=1
      shift
      ;;
    --sizes)
      require_option_value "$1" "${2:-}"
      SIZES_CSV="$2"
      SIZES_EXPLICIT=1
      shift 2
      ;;
    --output)
      require_option_value "$1" "${2:-}"
      COMPARE_RESULT="$2"
      shift 2
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

case "$PRESET" in
  local)
    ;;
  ci)
    [[ "$COMPILE_ITERATIONS_EXPLICIT" -eq 0 ]] && COMPILE_ITERATIONS=2
    [[ "$RUNTIME_RUNS_EXPLICIT" -eq 0 ]] && RUNTIME_RUNS=2
    [[ "$RUNTIME_ITERATIONS_EXPLICIT" -eq 0 ]] && RUNTIME_ITERATIONS=10000
    [[ "$VALIDATION_RUNS_EXPLICIT" -eq 0 ]] && VALIDATION_RUNS=1
    [[ "$SIZES_EXPLICIT" -eq 0 ]] && SIZES_CSV="10,50"
    ;;
  *)
    echo "--preset must be one of: local, ci" >&2
    exit 1
    ;;
esac

mkdir -p "$(dirname "$COMPARE_RESULT")" "$(dirname "$VALIDATION_BASELINE")"

declare -a compile_args=(--iterations "$COMPILE_ITERATIONS" --output "$COMPILE_RESULT")
declare -a runtime_args=(--runs "$RUNTIME_RUNS" --iterations "$RUNTIME_ITERATIONS" --output "$RUNTIME_RESULT")
declare -a validation_args=(--preset "$PRESET" --runs "$VALIDATION_RUNS" --output "$VALIDATION_RESULT")
if [[ -n "$SIZES_CSV" ]]; then
  compile_args+=(--sizes "$SIZES_CSV")
  runtime_args+=(--sizes "$SIZES_CSV")
  validation_args+=(--sizes "$SIZES_CSV")
fi

"$ROOT_DIR/Benchmarks/run-compile-bench.sh" "${compile_args[@]}"
"$ROOT_DIR/Benchmarks/run-runtime-bench.sh" "${runtime_args[@]}"
"$ROOT_DIR/Benchmarks/run-validation-bench.sh" "${validation_args[@]}"

set +e
python3 - \
  "$VALIDATION_RESULT" \
  "$VALIDATION_BASELINE" \
  "$VALIDATION_COMPARE_RESULT" \
  "$VALIDATION_COMPARE_SUMMARY" \
  "$VALIDATION_THRESHOLD_PERCENT" \
  "$UPDATE_VALIDATION_BASELINE" \
  <<'PY'
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

validation_path = Path(sys.argv[1])
baseline_path = Path(sys.argv[2])
compare_json_path = Path(sys.argv[3])
compare_md_path = Path(sys.argv[4])
threshold_percent = float(sys.argv[5])
update_baseline = sys.argv[6] == "1"

current = json.loads(validation_path.read_text())

def now():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def mean_metric(entry, key):
    return float(entry[key]["mean"])

def scenario_key(entry):
    return (entry["scenario"], int(entry["size"]))

def reason_map(entry):
    return dict(entry.get("warm_reason_frequencies", {}))

def write_outputs(payload, markdown):
    compare_json_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    compare_md_path.write_text(markdown)

def reason_label(reason):
    labels = {
        "cache-hit-metadata": "metadata cache hit",
        "cache-hit-content-hash": "content-hash reuse",
        "cache-miss-content-changed": "content changed",
        "cache-miss-new-file": "new file detected",
        "cache-miss-deleted-file": "file deleted",
        "cache-miss-manifest-version": "manifest version changed",
        "live-run-custom-init-failure": "custom init validation failed",
        "live-run-dag-validation": "live DAG validation ran",
    }
    return labels.get(reason, reason)

current_by_key = {scenario_key(entry): entry for entry in current["validation"]}

if update_baseline or not baseline_path.exists():
    shutil.copyfile(validation_path, baseline_path)
    payload = {
        "schema_version": 1,
        "generated_at": now(),
        "status": "baseline-updated",
        "baseline_path": str(baseline_path.name),
        "threshold_percent": threshold_percent,
        "current_signature": {
            "swift_version": current.get("swift_version", ""),
            "preset": current.get("config", {}).get("preset", ""),
        },
        "offending_metrics": [],
        "comparisons": [],
        "reason_frequency_deltas": [],
    }
    markdown = """# Validation Benchmark Compare\n\n- Status: `baseline-updated`\n- Validation baseline was created or refreshed from the current benchmark run.\n- Re-run `Benchmarks/compare.sh` without `--update-validation-baseline` to enable regression gating.\n"""
    write_outputs(payload, markdown)
    sys.exit(0)

baseline = json.loads(baseline_path.read_text())
baseline_by_key = {scenario_key(entry): entry for entry in baseline["validation"]}

comparisons = []
offending_metrics = []
reason_frequency_deltas = []

for key in sorted(set(current_by_key) | set(baseline_by_key)):
    current_entry = current_by_key.get(key)
    baseline_entry = baseline_by_key.get(key)
    scenario_name = key[0]
    size = key[1]
    if current_entry is None:
      continue
    if baseline_entry is None:
      offending_metrics.append({
          "scenario": scenario_name,
          "size": size,
          "metric": "scenario-presence",
          "status": "new-scenario",
      })
      continue

    for metric_key, metric_label in (
        ("graph_scan", "graph-scan-ms"),
        ("coordinator_cold", "coordinator-cold-ms"),
        ("coordinator_warm", "coordinator-warm-ms"),
    ):
        current_mean = mean_metric(current_entry, metric_key)
        baseline_mean = mean_metric(baseline_entry, metric_key)
        delta = 0.0 if baseline_mean == 0 else ((current_mean - baseline_mean) / baseline_mean) * 100.0
        status = "pass" if delta <= threshold_percent else "fail"
        comparison = {
            "scenario": scenario_name,
            "size": size,
            "metric": metric_label,
            "current_mean_ms": round(current_mean, 3),
            "baseline_mean_ms": round(baseline_mean, 3),
            "delta_percent": round(delta, 2),
            "status": status,
        }
        comparisons.append(comparison)
        if status == "fail":
            offending_metrics.append(comparison)

    baseline_reasons = reason_map(baseline_entry)
    current_reasons = reason_map(current_entry)
    for reason in sorted(set(baseline_reasons) | set(current_reasons)):
        reason_frequency_deltas.append({
            "scenario": scenario_name,
            "size": size,
            "reason": reason,
            "reason_label": reason_label(reason),
            "baseline_count": int(baseline_reasons.get(reason, 0)),
            "current_count": int(current_reasons.get(reason, 0)),
        })

for key in sorted(set(baseline_by_key) - set(current_by_key)):
    offending_metrics.append({
        "scenario": key[0],
        "size": key[1],
        "metric": "scenario-presence",
        "status": "missing-from-current-run",
    })

status = "fail" if offending_metrics else "pass"
payload = {
    "schema_version": 1,
    "generated_at": now(),
    "status": status,
    "baseline_path": baseline_path.name,
    "threshold_percent": threshold_percent,
    "current_signature": {
        "swift_version": current.get("swift_version", ""),
        "preset": current.get("config", {}).get("preset", ""),
    },
    "baseline_signature": {
        "swift_version": baseline.get("swift_version", ""),
        "preset": baseline.get("config", {}).get("preset", ""),
    },
    "offending_metrics": offending_metrics,
    "comparisons": comparisons,
    "reason_frequency_deltas": reason_frequency_deltas,
}

lines = [
    "# Validation Benchmark Compare",
    "",
    f"- Status: `{status}`",
    f"- Threshold: `{threshold_percent:.2f}%`",
    f"- Current preset: `{current.get('config', {}).get('preset', '')}`",
    f"- Baseline preset: `{baseline.get('config', {}).get('preset', '')}`",
    f"- Current Swift: `{current.get('swift_version', '')}`",
    f"- Baseline Swift: `{baseline.get('swift_version', '')}`",
    "",
    "## Timing Comparison",
    "",
    "| Scenario | Size | Metric | Baseline | Current | Delta | Status |",
    "|---|---:|---|---:|---:|---:|---|",
]
for comparison in comparisons:
    lines.append(
        f"| `{comparison['scenario']}` | `{comparison['size']}` | `{comparison['metric']}` | "
        f"`{comparison['baseline_mean_ms']:.3f} ms` | `{comparison['current_mean_ms']:.3f} ms` | "
        f"`{comparison['delta_percent']:.2f}%` | `{comparison['status']}` |"
    )

lines.extend(["", "## Cache Reason Distribution", ""])
if reason_frequency_deltas:
    lines.extend([
        "| Scenario | Size | Reason | Baseline | Current |",
        "|---|---:|---|---:|---:|",
    ])
    for delta in reason_frequency_deltas:
        lines.append(
            f"| `{delta['scenario']}` | `{delta['size']}` | `{delta['reason_label']}` | "
            f"`{delta['baseline_count']}` | `{delta['current_count']}` |"
        )
else:
    lines.append("- none")

lines.extend(["", "## Offending Metrics", ""])
if offending_metrics:
    for item in offending_metrics:
        lines.append(
            f"- `{item['scenario']}` size `{item['size']}` metric `{item['metric']}` status `{item['status']}`"
        )
else:
    lines.append("- none")

write_outputs(payload, "\n".join(lines) + "\n")
sys.exit(1 if status == "fail" else 0)
PY
validation_compare_status=$?
set -e

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg generated_at "$generated_at" \
    --arg preset "$PRESET" \
    --arg validation_baseline "$(basename "$VALIDATION_BASELINE")" \
    --slurpfile compile "$COMPILE_RESULT" \
    --slurpfile runtime "$RUNTIME_RESULT" \
    --slurpfile validation "$VALIDATION_RESULT" \
    --slurpfile validation_compare "$VALIDATION_COMPARE_RESULT" \
    '{
      schema_version: 1,
      generated_at: $generated_at,
      preset: $preset,
      validation_baseline: $validation_baseline,
      compile: $compile[0],
      runtime: $runtime[0],
      validation: $validation[0],
      validation_compare: $validation_compare[0]
    }' >"$COMPARE_RESULT"
else
  cat >"$COMPARE_RESULT" <<JSON
{
  "schema_version": 1,
  "generated_at": "$generated_at",
  "preset": "$PRESET",
  "validation_baseline": "$(basename "$VALIDATION_BASELINE")",
  "compile_path": "$(basename "$COMPILE_RESULT")",
  "runtime_path": "$(basename "$RUNTIME_RESULT")",
  "validation_path": "$(basename "$VALIDATION_RESULT")",
  "validation_compare_path": "$(basename "$VALIDATION_COMPARE_RESULT")",
  "note": "Install jq for fully inlined compare output."
}
JSON
fi

echo "[bench-compare] Wrote $COMPARE_RESULT"
echo "[bench-compare] Wrote $VALIDATION_COMPARE_RESULT"
echo "[bench-compare] Wrote $VALIDATION_COMPARE_SUMMARY"
exit "$validation_compare_status"
