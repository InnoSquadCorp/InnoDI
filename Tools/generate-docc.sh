#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_DIR="${1:-$ROOT_DIR/.build/docc/InnoDI}"
TARGET="${2:-InnoDI}"
DOCC_PLUGIN_VERSION="1.5.0"
DOCS_RESOLVED_PATH="$ROOT_DIR/Tools/docc/Package.resolved"
INDEX_HTML_PATH="$OUTPUT_DIR/index.html"
INDEX_JSON_PATH="$OUTPUT_DIR/index/index.json"
NOT_FOUND_HTML_PATH="$OUTPUT_DIR/404.html"

if [[ ! -s "$DOCS_RESOLVED_PATH" ]]; then
  echo "DocC dependency lock is missing or empty: $DOCS_RESOLVED_PATH" >&2
  exit 1
fi

DOCS_WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/innodi-docc.XXXXXX")"
DOCS_PACKAGE_DIR="$DOCS_WORK_DIR/package"
DOCS_MANIFEST_PATH="$DOCS_PACKAGE_DIR/Package.swift"

cleanup() {
  rm -rf "$DOCS_WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
mkdir -p "$DOCS_PACKAGE_DIR"

rsync -a \
  --exclude '.build' \
  --exclude '.git' \
  --exclude '*.lproj/' \
  "$ROOT_DIR/" "$DOCS_PACKAGE_DIR/"

cp "$DOCS_RESOLVED_PATH" "$DOCS_PACKAGE_DIR/Package.resolved"

python3 - "$DOCS_MANIFEST_PATH" "$DOCC_PLUGIN_VERSION" <<'PY'
import pathlib
import re
import sys

manifest_path = pathlib.Path(sys.argv[1])
docc_plugin_version = sys.argv[2]
text = manifest_path.read_text()
dependency_line = f'        .package(url: "https://github.com/swiftlang/swift-docc-plugin", exact: "{docc_plugin_version}"),\n'

# The release package excludes DocC catalogs from ordinary Swift 6.4 builds to
# avoid an Xcode 27 preview SwiftPM unhandled-input diagnostic under
# -warnings-as-errors. This isolated package is specifically for DocC, so put
# those catalogs back into the plugin's target source-file view.
text = re.sub(
    r'documentationCatalogBuildExcludes\("[^"]+"\)',
    '[]',
    text,
)

if "swift-docc-plugin" in text:
    manifest_path.write_text(text)
    raise SystemExit(0)

pattern = re.compile(
    r"(dependencies:\s*\[\n(?:\s*\.package\(url: \"https://github\.com/swiftlang/swift-syntax\.git\", exact: \"603\.0\.2\"\),\n)?)",
    re.MULTILINE,
)
match = pattern.search(text)
if not match:
    raise SystemExit("Unable to locate dependencies section in Package.swift")

replacement = match.group(1) + dependency_line
manifest_path.write_text(text[:match.start(1)] + replacement + text[match.end(1):])
PY

echo "[docc] Generating DocC for target '$TARGET' -> $OUTPUT_DIR"
swift package \
  --package-path "$DOCS_PACKAGE_DIR" \
  --disable-automatic-resolution \
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
