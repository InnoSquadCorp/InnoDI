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

python3 - \
  "$OUTPUT_FILE" \
  "$DISABLED_BUDGET" \
  "$ENABLED_BUDGET" \
  "$SATURATED_BUDGET" \
  "$SNAPSHOT_BUDGET" \
  "$CONTENDED_BUDGET" <<'PY'
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
saturated_budget = float(sys.argv[4])
snapshot_budget = float(sys.argv[5])
contended_budget = float(sys.argv[6])
saturated = report.get("saturatedMeasurements")
if not isinstance(saturated, list) or [item.get("capacity") for item in saturated] != [64, 4096, 65536]:
    raise SystemExit("runtime trace benchmark must report every saturated capacity")
for item in saturated:
    capacity = item["capacity"]
    emitted = item.get("emittedEventCount")
    retained = item.get("retainedEventCount")
    dropped = item.get("droppedEventCount")
    record_cost = item.get("nanosecondsPerEvent")
    snapshot_cost = item.get("snapshotNanosecondsPerRetainedEvent")
    if retained != capacity or dropped != emitted - capacity:
        raise SystemExit(f"runtime trace capacity {capacity} lost ring-buffer accounting")
    for name, value in (("saturated", record_cost), ("snapshot", snapshot_cost)):
        if not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            raise SystemExit(f"runtime trace {name} measurement is invalid")
    if record_cost > saturated_budget:
        raise SystemExit(f"saturated runtime trace overhead exceeds its budget at capacity {capacity}")
    if snapshot_cost > snapshot_budget:
        raise SystemExit(f"runtime trace snapshot overhead exceeds its budget at capacity {capacity}")

contention = report.get("contention")
if not isinstance(contention, dict):
    raise SystemExit("runtime trace benchmark must report writer and snapshot contention")
if contention.get("retainedEventCount") != contention.get("capacity"):
    raise SystemExit("runtime trace contention did not saturate the buffer")
if contention.get("droppedEventCount") != contention.get("emittedEventCount") - contention.get("capacity"):
    raise SystemExit("runtime trace contention lost ring-buffer accounting")
contended = contention.get("nanosecondsPerEvent")
if not isinstance(contended, (int, float)) or not math.isfinite(contended) or contended < 0:
    raise SystemExit("runtime trace contention measurement is invalid")
if contended > contended_budget:
    raise SystemExit("contended runtime trace overhead exceeds its budget")
print(
    "Runtime trace performance: "
    f"disabled={disabled:.2f} ns/resolution (budget {disabled_budget:.2f}), "
    f"enabled={enabled:.2f} ns/event (budget {enabled_budget:.2f}), "
    f"saturated-max={max(item['nanosecondsPerEvent'] for item in saturated):.2f} ns/event "
    f"(budget {saturated_budget:.2f}), "
    f"snapshot-max={max(item['snapshotNanosecondsPerRetainedEvent'] for item in saturated):.2f} ns/event "
    f"(budget {snapshot_budget:.2f}), "
    f"contended={contended:.2f} ns/event (budget {contended_budget:.2f})"
)
if disabled > disabled_budget:
    raise SystemExit("disabled runtime trace overhead exceeds its budget")
if enabled > enabled_budget:
    raise SystemExit("enabled runtime trace overhead exceeds its budget")
PY
