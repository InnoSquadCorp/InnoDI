#!/usr/bin/env bash
set -euo pipefail

# Run the same strict, single-pass coverage contract locally, on main, and
# during release validation. Removing only derived coverage profiles prevents
# a previous invocation from inflating the next run while preserving SwiftPM's
# ordinary build cache.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SWIFT_PACKAGE_ARGUMENTS=(--package-path "$ROOT_DIR")
if [[ -n "${INNODI_COVERAGE_SCRATCH_PATH:-}" ]]; then
    SWIFT_PACKAGE_ARGUMENTS+=(
        --scratch-path "$INNODI_COVERAGE_SCRATCH_PATH"
    )
fi

BUILD_DIR="$(swift build "${SWIFT_PACKAGE_ARGUMENTS[@]}" --show-bin-path)"
COVERAGE_PROFILE_DIR="$BUILD_DIR/codecov"
if [[ "$BUILD_DIR" != /* || "$(basename "$COVERAGE_PROFILE_DIR")" != "codecov" \
    || "$(dirname "$COVERAGE_PROFILE_DIR")" != "$BUILD_DIR" ]]; then
    echo "::error::refusing to remove unexpected coverage profile directory '$COVERAGE_PROFILE_DIR'" >&2
    exit 1
fi
rm -rf "$COVERAGE_PROFILE_DIR"

COVERAGE_OUTPUT_DIR="${INNODI_COVERAGE_DIR:-coverage}"
TEST_LOG="$COVERAGE_OUTPUT_DIR/test-output.log"
rm -f \
    "$COVERAGE_OUTPUT_DIR/lcov.info" \
    "$COVERAGE_OUTPUT_DIR/report.txt" \
    "$COVERAGE_OUTPUT_DIR/summary.json" \
    "$COVERAGE_OUTPUT_DIR/summary.md" \
    "$TEST_LOG"
mkdir -p "$COVERAGE_OUTPUT_DIR"

# Record which suites dominate wall-clock time on success and on failure.
summarize_test_durations() {
    if [[ -n "${GITHUB_STEP_SUMMARY:-}" && -s "$TEST_LOG" ]]; then
        python3 -B Tools/summarize-test-durations.py "$TEST_LOG" \
            --title "Slowest test suites (coverage gate)" >> "$GITHUB_STEP_SUMMARY" || true
    fi
}
trap summarize_test_durations EXIT

# Synchronous compiler/CLI fixtures must not occupy the cooperative executor
# while an unrelated async contract's wall-clock limit is running. Serialize
# independent test cases, not the tasks/concurrency exercised inside each test.
# Keep every test, its time limit, and one fresh coverage pass unchanged.
swift test "${SWIFT_PACKAGE_ARGUMENTS[@]}" --no-parallel -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --enable-code-coverage \
    2>&1 | tee "$TEST_LOG"
INNODI_COVERAGE_BUILD_DIR="$BUILD_DIR" Tools/collect-coverage.sh

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
        echo "## Code coverage"
        echo
        cat "$COVERAGE_OUTPUT_DIR/summary.md"
    } >> "$GITHUB_STEP_SUMMARY"
fi

python3 Tools/check-coverage-floor.py \
    --summary "$COVERAGE_OUTPUT_DIR/summary.json"
