#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: Tools/package-release-docc.sh --source <docc-directory> --output <archive.tar.gz>

Create a byte-for-byte reproducible InnoDI DocC archive. The archive always
uses the root directory name "InnoDI", normalized metadata, sorted entries,
and a gzip header without a source name or timestamp.
USAGE
}

SOURCE_DIR=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "--source requires a value" >&2; exit 2; }
      SOURCE_DIR="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "--output requires a value" >&2; exit 2; }
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE_DIR" || -z "$OUTPUT_PATH" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "DocC source directory does not exist: $SOURCE_DIR" >&2
  exit 1
fi
SOURCE_DIR="$(cd "$SOURCE_DIR" && pwd -P)"

for tool in cp find gzip mkdir mktemp mv sort tar touch; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Required packaging tool is unavailable: $tool" >&2
    exit 1
  fi
done

OUTPUT_DIRECTORY="$(dirname "$OUTPUT_PATH")"
OUTPUT_FILENAME="$(basename "$OUTPUT_PATH")"
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd "$OUTPUT_DIRECTORY" && pwd -P)"
OUTPUT_PATH="$OUTPUT_DIRECTORY/$OUTPUT_FILENAME"
case "$OUTPUT_PATH" in
  "$SOURCE_DIR"|"$SOURCE_DIR"/*)
    echo "Output archive must be outside the DocC source directory." >&2
    exit 1
    ;;
esac

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/innodi-release-docc.XXXXXX")"
TEMP_OUTPUT="$(mktemp "$OUTPUT_DIRECTORY/.innodi-docc.XXXXXX")"
TEMP_TAR="$STAGING_ROOT/innodi-docc.tar"

cleanup() {
  rm -rf "$STAGING_ROOT"
  rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT

umask 022
mkdir -p "$STAGING_ROOT/content/InnoDI"
COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
  cp -R "$SOURCE_DIR"/. "$STAGING_ROOT/content/InnoDI"/

find "$STAGING_ROOT/content/InnoDI" -type d -exec chmod 0755 {} +
find "$STAGING_ROOT/content/InnoDI" -type f -exec chmod 0644 {} +
TZ=UTC find "$STAGING_ROOT/content/InnoDI" \
  -exec touch -h -t 198001010000.00 {} +

(
  cd "$STAGING_ROOT/content"
  find InnoDI -print0 \
    | LC_ALL=C sort -z \
    | COPYFILE_DISABLE=1 COPY_EXTENDED_ATTRIBUTES_DISABLE=1 \
      tar \
        --null \
        --no-recursion \
        --no-xattrs \
        --no-mac-metadata \
        --no-acls \
        --no-fflags \
        --format paxr \
        --uid 0 \
        --gid 0 \
        --uname root \
        --gname root \
        -T - \
        -cf "$TEMP_TAR"
)

gzip -n -9 < "$TEMP_TAR" > "$TEMP_OUTPUT"
chmod 0644 "$TEMP_OUTPUT"
mv -f "$TEMP_OUTPUT" "$OUTPUT_PATH"
