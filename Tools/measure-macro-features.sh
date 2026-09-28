#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
OUTPUT="${INNODI_FEATURE_BENCH_REPORT:-build/macro-feature-performance-report.json}"
CANDIDATE="$(git rev-parse HEAD)"
CLEAN=false
if [[ -z "$(git status --porcelain --untracked-files=all)" ]]; then CLEAN=true; fi
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/innodi-feature-bench.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

INNODI_FEATURE_BENCH_OUTPUT="$TEMP_DIR/report.json" \
INNODI_FEATURE_BENCH_SHA="$CANDIDATE" \
INNODI_FEATURE_BENCH_CLEAN="$CLEAN" \
SWIFT_VERSION="$(swift --version)" \
swift test --no-parallel --filter MacroFeaturePerformanceBenchmark/measureFeatures

if [[ "$(git rev-parse HEAD)" != "$CANDIDATE" ]]; then
  echo "feature benchmark candidate changed while measuring" >&2
  exit 1
fi
if [[ "$CLEAN" == true && -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "feature benchmark clean source changed while measuring" >&2
  exit 1
fi
python3 Tools/validate-macro-feature-report.py "$TEMP_DIR/report.json" "$CANDIDATE"
mkdir -p "$(dirname "$OUTPUT")"
mv "$TEMP_DIR/report.json" "$OUTPUT"
echo "Feature workloads recorded separately: $OUTPUT (report-only; no calibrated budgets)"
