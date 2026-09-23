#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUDGET_FILE="${INNODI_RUNTIME_TRACE_BUDGET:-Tools/runtime-trace-performance-budget.json}"
OUTPUT_FILE="${INNODI_RUNTIME_TRACE_REPORT:-build/runtime-trace-performance-report.json}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/innodi-runtime-trace.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

read -r ITERATIONS ENABLED_ITERATIONS DISABLED_BUDGET ENABLED_BUDGET SATURATED_BUDGET SNAPSHOT_BUDGET CONTENDED_BUDGET < <(
  python3 - "$BUDGET_FILE" <<'PY'
import json, math, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
if data.get("schemaVersion") != 1:
    raise SystemExit("runtime trace budget schemaVersion must equal 1")
values = [
    data.get("iterations"),
    data.get("enabledIterations"),
    data.get("disabledNetNanosecondsPerResolution"),
    data.get("enabledNanosecondsPerEvent"),
    data.get("saturatedNanosecondsPerEvent"),
    data.get("snapshotNanosecondsPerRetainedEvent"),
    data.get("contendedNanosecondsPerEvent"),
]
if not all(isinstance(value, (int, float)) and not isinstance(value, bool)
           and math.isfinite(value) and value > 0 for value in values):
    raise SystemExit("runtime trace budgets must be finite positive numbers")
print(*values)
PY
)

swiftc -O -parse-as-library \
  Sources/InnoDI/DITracing.swift \
  Tools/RuntimeTraceBenchmark.swift \
  -o "$TEMP_DIR/runtime-trace-benchmark"

mkdir -p "$(dirname "$OUTPUT_FILE")"
"$TEMP_DIR/runtime-trace-benchmark" \
  --iterations "$ITERATIONS" \
  --enabled-iterations "$ENABLED_ITERATIONS" \
  > "$OUTPUT_FILE"

python3 Tools/check-runtime-trace-report.py \
  "$OUTPUT_FILE" \
  "$DISABLED_BUDGET" \
  "$ENABLED_BUDGET" \
  "$SATURATED_BUDGET" \
  "$SNAPSHOT_BUDGET" \
  "$CONTENDED_BUDGET"
