#!/usr/bin/env bash
# Measure time-to-first-binary for an InnoDI-consuming target after clearing
# both the SPM scratch directory and the user-level SwiftPM cache. This is the
# single source of truth for root-package and synthetic-consumer build cost:
# it forces a from-scratch swift-syntax + macro plugin compilation so the
# dominant cost surface is reproducible instead of depending on hosted-runner
# cache state. The report distinguishes a SwiftSyntax prebuilt from a source
# fallback so a toolchain publishing gap is not misdiagnosed as InnoDI work.
#
# Usage:
#   Tools/cold-build-benchmark.sh --target root [--config release]
#   Tools/cold-build-benchmark.sh --target consumer --bindings 100
#
# Output: a single-line JSON object on stdout with the elapsed milliseconds
# and a few environment markers. Exit non-zero if the build fails. Designed
# to be parsed by CI artifact uploads.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TARGET="root"
CONFIG="release"
BINDINGS="100"
KEEP_USER_CACHE=0
BUILD_LOG_PATH=""

usage() {
    cat <<USAGE
Usage: Tools/cold-build-benchmark.sh [options]

Options:
  --target <root|consumer>     What to build (default: root)
  --config <debug|release>     Build configuration (default: release)
  --bindings <N>               Synthetic consumer @Provide count (default: 100)
  --keep-user-cache            Skip wiping ~/Library/Caches/org.swift.swiftpm
  --build-log <path>           Preserve the underlying Swift build log
  --help                       Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)
            TARGET="${2:?--target requires a value}"
            shift 2
            ;;
        --config)
            CONFIG="${2:?--config requires a value}"
            shift 2
            ;;
        --bindings)
            BINDINGS="${2:?--bindings requires a value}"
            shift 2
            ;;
        --keep-user-cache)
            KEEP_USER_CACHE=1
            shift
            ;;
        --build-log)
            BUILD_LOG_PATH="${2:?--build-log requires a value}"
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

case "$TARGET" in
    root|consumer) ;;
    *)
        echo "--target must be 'root' or 'consumer'" >&2
        exit 1
        ;;
esac

case "$CONFIG" in
    debug|release) ;;
    *)
        echo "--config must be 'debug' or 'release'" >&2
        exit 1
        ;;
esac

if ! [[ "$BINDINGS" =~ ^[1-9][0-9]*$ ]]; then
    echo "--bindings must be a positive integer" >&2
    exit 1
fi

clear_caches() {
    local package_dir="$1"
    rm -rf "$package_dir/.build" "$package_dir/.swiftpm/cache"
    if [[ "$KEEP_USER_CACHE" == "0" ]]; then
        rm -rf "${HOME:?}/Library/Caches/org.swift.swiftpm" || true
        rm -rf "${HOME:?}/Library/org.swift.swiftpm" || true
    fi
}

now_ns() {
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000000000'
}

if [[ "$TARGET" == "root" ]]; then
    PACKAGE_DIR="$ROOT_DIR"
    SCENARIO="innodi-root"
else
    PACKAGE_DIR="$ROOT_DIR/Tools/.synthetic/SyntheticConsumer"
    SCENARIO="synthetic-consumer-${BINDINGS}"
    mkdir -p "$ROOT_DIR/Tools/.synthetic"
    swift "$ROOT_DIR/Tools/generate-synthetic-consumer.swift" \
        "$ROOT_DIR/Tools/.synthetic/SyntheticConsumer" "$BINDINGS" 1>&2
fi

clear_caches "$PACKAGE_DIR"

if [[ -z "$BUILD_LOG_PATH" ]]; then
    TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/innodi-cold-build.XXXXXX")"
    trap 'rm -rf "$TEMP_DIR"' EXIT
    BUILD_LOG_PATH="$TEMP_DIR/build.log"
elif [[ "$BUILD_LOG_PATH" != /* ]]; then
    BUILD_LOG_PATH="$(pwd -P)/$BUILD_LOG_PATH"
fi
mkdir -p "$(dirname "$BUILD_LOG_PATH")"

START=$(now_ns)
swift build --package-path "$PACKAGE_DIR" -c "$CONFIG" 2>&1 \
    | tee "$BUILD_LOG_PATH" >&2
END=$(now_ns)

ELAPSED_MS=$(awk -v s="$START" -v e="$END" 'BEGIN { printf "%.3f", (e - s) / 1000000.0 }')
SWIFT_VERSION=$(swift --version 2>/dev/null | head -n 1)
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -n 1)

PREBUILT_ARCHIVE="$(
    find "$PACKAGE_DIR/.build/prebuilts/swift-syntax" \
        -type f -name 'libMacroSupport.a' -print -quit 2>/dev/null || true
)"
if grep -E -q '(^|\] )(Compiling|Emitting module) SwiftSyntax( |$)' "$BUILD_LOG_PATH"; then
    SWIFT_SYNTAX_MODE="source"
elif [[ -n "$PREBUILT_ARCHIVE" ]]; then
    SWIFT_SYNTAX_MODE="prebuilt"
elif grep -q 'badResponseStatusCode(404)' "$BUILD_LOG_PATH"; then
    SWIFT_SYNTAX_MODE="prebuilt-unavailable"
else
    SWIFT_SYNTAX_MODE="not-observed"
fi

printf '{"scenario":"%s","config":"%s","elapsed_ms":%s,"swift_syntax_mode":"%s","xcode_version":"%s","swift_version":"%s","timestamp":"%s"}\n' \
    "$SCENARIO" \
    "$CONFIG" \
    "$ELAPSED_MS" \
    "$SWIFT_SYNTAX_MODE" \
    "${XCODE_VERSION//\"/}" \
    "${SWIFT_VERSION//\"/}" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
