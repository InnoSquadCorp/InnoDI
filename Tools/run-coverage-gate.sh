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
rm -f \
    "$COVERAGE_OUTPUT_DIR/lcov.info" \
    "$COVERAGE_OUTPUT_DIR/report.txt" \
    "$COVERAGE_OUTPUT_DIR/summary.json" \
    "$COVERAGE_OUTPUT_DIR/summary.md"

swift test "${SWIFT_PACKAGE_ARGUMENTS[@]}" -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --enable-code-coverage
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
