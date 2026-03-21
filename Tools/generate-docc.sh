#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${1:-$ROOT_DIR/.build/docc/InnoDI}"
TARGET="${2:-InnoDI}"
INDEX_HTML_PATH="$OUTPUT_DIR/index.html"
INDEX_JSON_PATH="$OUTPUT_DIR/index/index.json"
NOT_FOUND_HTML_PATH="$OUTPUT_DIR/404.html"

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

python3 - "$INDEX_JSON_PATH" "$INDEX_HTML_PATH" <<'PY'
import json
import pathlib
import re
import sys

index_json_path = pathlib.Path(sys.argv[1])
index_html_path = pathlib.Path(sys.argv[2])

if not index_json_path.exists() or not index_html_path.exists():
    raise SystemExit(0)

index_data = json.loads(index_json_path.read_text())
default_path = None
for entries in index_data.get("interfaceLanguages", {}).values():
    if entries and entries[0].get("path"):
        default_path = entries[0]["path"]
        break

if not default_path:
    raise SystemExit(0)

html = index_html_path.read_text()
if "window.__doccRootRedirectApplied" in html:
    raise SystemExit(0)

match = re.search(r'<script>var baseUrl = "([^"]+)"</script>', html)
if not match:
    raise SystemExit(0)

base_url = match.group(1)
replacement = (
    f'<script>var baseUrl = "{base_url}"</script>'
    '<script>(function(){'
    'window.__doccRootRedirectApplied=true;'
    'var rootPaths=[baseUrl.replace(/\\/$/, ""),baseUrl];'
    f'var defaultPath={json.dumps(default_path)};'
    'if(rootPaths.indexOf(window.location.pathname)!==-1){'
    'window.history.replaceState({}, "", baseUrl.replace(/\\/$/, "") + defaultPath);'
    '}'
    '})();</script>'
)
index_html_path.write_text(html.replace(match.group(0), replacement, 1))
PY

cp "$INDEX_HTML_PATH" "$NOT_FOUND_HTML_PATH"

echo "[docc] Done"
