#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG=""
SOURCE_PATH=""
INNODI_REPO="${INNODI_REPO:-git@github.com:InnoSquadCorp/InnoDI.git}"
OUTPUT_DIR="$ROOT_DIR/Artifacts"
RELEASE_URL=""
UPDATE_PACKAGE=0

usage() {
  cat <<USAGE
Usage: Tools/prepare-release-artifact.sh --tag <tag> [options]

Options:
  --tag <tag>              InnoDI tag/version embedded in the artifact bundle.
  --source-path <path>     Existing InnoDI checkout to build instead of cloning.
  --repo <url>             InnoDI git repository (default: $INNODI_REPO).
  --output-dir <path>      Artifact output directory (default: Artifacts).
  --release-url <url>      Remote zip URL to write into Package.swift.
  --update-package         Update Package.swift binary target to use --release-url/checksum.
  --help                   Show this help.
USAGE
}

require_value() {
  local option="$1"
  local value="${2:-}"
  if [[ -z "$value" || "$value" == -* ]]; then
    echo "Error: $option requires a value." >&2
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      require_value "$1" "${2:-}"
      TAG="$2"
      shift 2
      ;;
    --source-path)
      require_value "$1" "${2:-}"
      SOURCE_PATH="$2"
      shift 2
      ;;
    --repo)
      require_value "$1" "${2:-}"
      INNODI_REPO="$2"
      shift 2
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --release-url)
      require_value "$1" "${2:-}"
      RELEASE_URL="$2"
      shift 2
      ;;
    --update-package)
      UPDATE_PACKAGE=1
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

if [[ -z "$TAG" ]]; then
  echo "Error: --tag is required." >&2
  usage
  exit 1
fi

if [[ "$UPDATE_PACKAGE" -eq 1 && -z "$RELEASE_URL" ]]; then
  echo "Error: --update-package requires --release-url." >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/innodi-validation-tools.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ -n "$SOURCE_PATH" ]]; then
  SOURCE_DIR="$(cd "$SOURCE_PATH" && pwd)"
else
  SOURCE_DIR="$TMP_DIR/InnoDI"
  git clone --depth 1 --branch "$TAG" "$INNODI_REPO" "$SOURCE_DIR"
fi

mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

(
  cd "$SOURCE_DIR"
  swift build -c release --product InnoDI-DAGValidationCoordinator
)

BINARY_PATH="$SOURCE_DIR/.build/release/InnoDI-DAGValidationCoordinator"
if [[ ! -x "$BINARY_PATH" ]]; then
  echo "Error: expected executable at $BINARY_PATH" >&2
  exit 1
fi

TRIPLE="$(
  swiftc -print-target-info \
    | sed -n 's/.*"triple"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
)"
if [[ -z "$TRIPLE" ]]; then
  echo "Error: unable to determine Swift target triple." >&2
  exit 1
fi

BUNDLE_NAME="InnoDIPrebuiltDAGValidationCoordinator.artifactbundle"
BUNDLE_PATH="$OUTPUT_DIR/$BUNDLE_NAME"
VARIANT_DIR="InnoDIPrebuiltDAGValidationCoordinator-$TRIPLE"
rm -rf "$BUNDLE_PATH"
mkdir -p "$BUNDLE_PATH/$VARIANT_DIR/bin"
cp "$BINARY_PATH" "$BUNDLE_PATH/$VARIANT_DIR/bin/InnoDIPrebuiltDAGValidationCoordinator"

cat > "$BUNDLE_PATH/info.json" <<JSON
{
  "schemaVersion": "1.0",
  "artifacts": {
    "InnoDIPrebuiltDAGValidationCoordinator": {
      "version": "$TAG",
      "type": "executable",
      "variants": [
        {
          "path": "$VARIANT_DIR/bin/InnoDIPrebuiltDAGValidationCoordinator",
          "supportedTriples": [
            "$TRIPLE"
          ]
        }
      ]
    }
  }
}
JSON

ZIP_NAME="InnoDIPrebuiltDAGValidationCoordinator-$TAG.artifactbundle.zip"
ZIP_PATH="$OUTPUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
(
  cd "$OUTPUT_DIR"
  /usr/bin/zip -qry "$ZIP_NAME" "$BUNDLE_NAME"
)

CHECKSUM="$(swift package compute-checksum "$ZIP_PATH")"

update_package_manifest() {
  local package_path="$ROOT_DIR/Package.swift"
  local updated_path="$TMP_DIR/Package.swift.updated"

  set +e
  awk -v release_url="$RELEASE_URL" -v checksum="$CHECKSUM" '
    function emitReplacement(indent) {
      print indent ".binaryTarget("
      print indent "    name: \"InnoDIPrebuiltDAGValidationCoordinator\","
      print indent "    url: \"" release_url "\","
      print indent "    checksum: \"" checksum "\""
      print indent "),"
    }

    /^[[:space:]]*\.binaryTarget\([[:space:]]*$/ {
      capture = 1
      matched = 0
      block = $0 ORS
      indent = substr($0, 1, match($0, /\./) - 1)
      next
    }

    capture {
      block = block $0 ORS
      if ($0 ~ /name:[[:space:]]*"InnoDIPrebuiltDAGValidationCoordinator"/) {
        matched = 1
      }
      if ($0 ~ /^[[:space:]]*\),[[:space:]]*$/) {
        if (matched) {
          emitReplacement(indent)
          found = 1
        } else {
          printf "%s", block
        }
        capture = 0
        matched = 0
        block = ""
      }
      next
    }

    { print }

    END {
      if (capture) {
        printf "%s", block
      }
      if (!found) {
        exit 42
      }
    }
  ' "$package_path" > "$updated_path"
  local awk_status=$?
  set -e

  if [[ "$awk_status" -ne 0 ]]; then
    rm -f "$updated_path"
    echo "Error: unable to find InnoDIPrebuiltDAGValidationCoordinator binary target in $package_path." >&2
    exit 1
  fi

  mv "$updated_path" "$package_path"
}

if [[ "$UPDATE_PACKAGE" -eq 1 ]]; then
  update_package_manifest
fi

cat <<SUMMARY
Artifact bundle: $BUNDLE_PATH
Zip: $ZIP_PATH
Checksum: $CHECKSUM
Triple: $TRIPLE
SUMMARY
