#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CANDIDATE_SHA="$(git rev-parse HEAD)"
EXPECTED_SHA="${INNODI_RUNTIME_TRACE_EXPECTED_SHA:-}"
SOURCE_TREE_CLEAN=false
if [[ -z "$(git status --porcelain --untracked-files=all)" ]]; then
  SOURCE_TREE_CLEAN=true
fi
if [[ -n "$EXPECTED_SHA" ]] && { [[ "$EXPECTED_SHA" != "$CANDIDATE_SHA" ]] || [[ "$SOURCE_TREE_CLEAN" != true ]]; }; then
  echo "runtime trace requires a clean checkout of the exact candidate SHA" >&2
  exit 1
fi
COMPILER_VERSION="$(swiftc --version)"

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
if any(type(data.get(key)) is not int or data[key] <= 0 for key in ("iterations", "enabledIterations")):
    raise SystemExit("runtime trace budget iterations must be positive integers")
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
  --candidate-sha "$CANDIDATE_SHA" \
  --source-tree-clean "$SOURCE_TREE_CLEAN" \
  --compiler-version "$COMPILER_VERSION" \
  > "$OUTPUT_FILE"

if [[ -n "$EXPECTED_SHA" ]] && { [[ "$(git rev-parse HEAD)" != "$EXPECTED_SHA" ]] || [[ -n "$(git status --porcelain --untracked-files=all)" ]]; }; then
  echo "runtime trace candidate changed while measuring" >&2
  exit 1
fi

python3 Tools/check-runtime-trace-report.py \
  "$OUTPUT_FILE" \
  "$DISABLED_BUDGET" \
  "$ENABLED_BUDGET" \
  "$SATURATED_BUDGET" \
  "$SNAPSHOT_BUDGET" \
  "$CONTENDED_BUDGET" \
  "$EXPECTED_SHA"
