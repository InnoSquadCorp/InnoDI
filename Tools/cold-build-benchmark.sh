#!/usr/bin/env bash
# Measure time-to-first-binary for an InnoDI-consuming target after clearing
# both the SPM scratch directory and the user-level SwiftPM cache. Unlike
# `consumer-benchmark.yml`, which runs against a pre-warmed runner, this
# script forces a from-scratch swift-syntax + macro plugin compilation so
# the dominant cost surface is observable.
#
# Usage:
#   Tools/cold-build-benchmark.sh --target root [--config release]
#   Tools/cold-build-benchmark.sh --target consumer --bindings 100
#
# Output: a single-line JSON object on stdout with the elapsed milliseconds,
# the binary path, and a few environment markers. Exit non-zero if the build
# fails. Designed to be parsed by CI artifact uploads.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

TARGET="root"
CONFIG="release"
BINDINGS="100"
KEEP_USER_CACHE=0

usage() {
    cat <<USAGE
Usage: Tools/cold-build-benchmark.sh [options]

Options:
  --target <root|consumer>     What to build (default: root)
  --config <debug|release>     Build configuration (default: release)
  --bindings <N>               Synthetic consumer @Provide count (default: 100)
  --keep-user-cache            Skip wiping ~/Library/Caches/org.swift.swiftpm
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
        "$ROOT_DIR/Tools/.synthetic/SyntheticConsumer" "$BINDINGS"
fi

clear_caches "$PACKAGE_DIR"

START=$(now_ns)
swift build --package-path "$PACKAGE_DIR" -c "$CONFIG" 1>&2
END=$(now_ns)

ELAPSED_MS=$(awk -v s="$START" -v e="$END" 'BEGIN { printf "%.3f", (e - s) / 1000000.0 }')
SWIFT_VERSION=$(swift --version 2>/dev/null | head -n 1)

printf '{"scenario":"%s","config":"%s","elapsed_ms":%s,"swift_version":"%s","timestamp":"%s"}\n' \
    "$SCENARIO" \
    "$CONFIG" \
    "$ELAPSED_MS" \
    "${SWIFT_VERSION//\"/}" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
