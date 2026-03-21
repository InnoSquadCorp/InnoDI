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

# Some DocC frontend builds unconditionally fetch theme-settings.json.
# Generate an empty settings file when DocC doesn't emit one.
THEME_SETTINGS_PATH="$OUTPUT_DIR/theme-settings.json"
if [[ ! -f "$THEME_SETTINGS_PATH" ]]; then
  printf '{}\n' > "$THEME_SETTINGS_PATH"
fi

echo "[docc] Done"
