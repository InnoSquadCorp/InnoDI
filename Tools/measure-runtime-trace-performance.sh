#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

BUDGET_FILE="${INNODI_RUNTIME_TRACE_BUDGET:-Tools/runtime-trace-performance-budget.json}"
OUTPUT_FILE="${INNODI_RUNTIME_TRACE_REPORT:-build/runtime-trace-performance-report.json}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/innodi-runtime-trace.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

read -r ITERATIONS ENABLED_ITERATIONS DISABLED_BUDGET ENABLED_BUDGET < <(
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

python3 - \
  "$OUTPUT_FILE" \
  "$DISABLED_BUDGET" \
  "$ENABLED_BUDGET" <<'PY'
import json, math, sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
disabled = report.get("disabledNetNanosecondsPerResolution")
enabled = report.get("enabledNanosecondsPerEvent")
expected_events = report.get("enabledIterations", 0) * 2
if report.get("schemaVersion") != 1:
    raise SystemExit("runtime trace report schemaVersion must equal 1")
if report.get("recordedEventCount") != expected_events:
    raise SystemExit("runtime trace benchmark lost enabled events")
for name, value in (("disabled", disabled), ("enabled", enabled)):
    if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
        raise SystemExit(f"runtime trace {name} measurement is invalid")
disabled_budget = float(sys.argv[2])
enabled_budget = float(sys.argv[3])
print(
    "Runtime trace performance: "
    f"disabled={disabled:.2f} ns/resolution (budget {disabled_budget:.2f}), "
    f"enabled={enabled:.2f} ns/event (budget {enabled_budget:.2f})"
)
if disabled > disabled_budget:
    raise SystemExit("disabled runtime trace overhead exceeds its budget")
if enabled > enabled_budget:
    raise SystemExit("enabled runtime trace overhead exceeds its budget")
PY
