#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${1:-$ROOT_DIR/.build/docc/InnoDI}"
TARGET="${2:-InnoDI}"

mkdir -p "$OUTPUT_DIR"

echo "[docc] Generating DocC for target '$TARGET' -> $OUTPUT_DIR"
swift package \
  --allow-writing-to-directory "$OUTPUT_DIR" \
  generate-documentation \
  --target "$TARGET" \
  --output-path "$OUTPUT_DIR" \
  --disable-indexing \
  --transform-for-static-hosting \
  --hosting-base-path InnoDI

echo "[docc] Done"
