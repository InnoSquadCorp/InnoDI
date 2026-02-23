#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILE_RESULT="$ROOT_DIR/Benchmarks/results/compile.json"
RUNTIME_RESULT="$ROOT_DIR/Benchmarks/results/runtime.json"
COMPARE_RESULT="$ROOT_DIR/Benchmarks/results/compare.json"

COMPILE_ITERATIONS=5
RUNTIME_RUNS=5
RUNTIME_ITERATIONS=100000
SIZES_CSV=""

usage() {
  cat <<USAGE
Usage: Benchmarks/compare.sh [options]

Options:
  --compile-iterations <N>   Compile benchmark iterations (default: 5)
  --runtime-runs <N>         Runtime benchmark sample runs (default: 5)
  --runtime-iterations <N>   Runtime resolve iterations per sample (default: 100000)
  --sizes <CSV>              Comma-separated scenario sizes (default: 10,50,100,250)
  --output <PATH>            Comparison output JSON (default: Benchmarks/results/compare.json)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compile-iterations)
      COMPILE_ITERATIONS="$2"
      shift 2
      ;;
    --runtime-runs)
      RUNTIME_RUNS="$2"
      shift 2
      ;;
    --runtime-iterations)
      RUNTIME_ITERATIONS="$2"
      shift 2
      ;;
    --sizes)
      SIZES_CSV="$2"
      shift 2
      ;;
    --output)
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

mkdir -p "$(dirname "$COMPARE_RESULT")"

declare -a compile_args=(--iterations "$COMPILE_ITERATIONS" --output "$COMPILE_RESULT")
declare -a runtime_args=(--runs "$RUNTIME_RUNS" --iterations "$RUNTIME_ITERATIONS" --output "$RUNTIME_RESULT")
if [[ -n "$SIZES_CSV" ]]; then
  compile_args+=(--sizes "$SIZES_CSV")
  runtime_args+=(--sizes "$SIZES_CSV")
fi

"$ROOT_DIR/Benchmarks/run-compile-bench.sh" "${compile_args[@]}"
"$ROOT_DIR/Benchmarks/run-runtime-bench.sh" "${runtime_args[@]}"

generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg generated_at "$generated_at" \
    --slurpfile compile "$COMPILE_RESULT" \
    --slurpfile runtime "$RUNTIME_RESULT" \
    '{
      generated_at: $generated_at,
      compile: $compile[0],
      runtime: $runtime[0]
    }' >"$COMPARE_RESULT"
else
  cat >"$COMPARE_RESULT" <<JSON
{
  "generated_at": "$generated_at",
  "compile_path": "$(basename "$COMPILE_RESULT")",
  "runtime_path": "$(basename "$RUNTIME_RESULT")",
  "note": "Install jq for fully inlined compare output."
}
JSON
fi

echo "[bench-compare] Wrote $COMPARE_RESULT"
