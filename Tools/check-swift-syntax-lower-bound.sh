#!/usr/bin/env bash
set -euo pipefail

# Tools/check-swift-syntax-lower-bound.sh
#
# Package.swift accepts a closed SwiftSyntax range. Package.resolved and every
# ordinary lane use its upper bound. This script proves the lower bound, which
# a consumer graph gets when another macro package holds SwiftSyntax below the
# upper bound.
#
# It copies the package to a scratch directory, pins SwiftSyntax to the lower
# bound there, and runs every in-process test target under the coverage gate's
# strict flags. The macro plugin that expands the runtime, SwiftUI and testing
# fixtures is therefore built against the lower bound too. The working tree
# and its Package.resolved are never modified.
#
# Skipped: InnoDIBuildSupportTests and the fix-it consumer build. They build
# separate fixture packages, which resolve SwiftSyntax on their own and so say
# nothing about the lower bound.
#
# Environment:
#   INNODI_SYNTAX_LOWER_BOUND_DIR  scratch directory
#                                  (default: build/swift-syntax-lower-bound)

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

requirement="$(sed -n 's/.*swift-syntax\.git", "\([0-9][0-9.]*\)"\.\.\."\([0-9][0-9.]*\)").*/\1 \2/p' Package.swift)"
read -r LOWER UPPER <<<"$requirement"
if [[ -z "${LOWER:-}" || -z "${UPPER:-}" ]]; then
    echo "[syntax-lower-bound] Package.swift has no closed SwiftSyntax range" >&2
    exit 1
fi

WORK_DIR="${INNODI_SYNTAX_LOWER_BOUND_DIR:-build/swift-syntax-lower-bound}"
PACKAGE_DIR="$WORK_DIR/package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"
rsync -a \
    --exclude '.git' \
    --exclude '.build' \
    --exclude 'build' \
    --exclude 'coverage' \
    "$ROOT_DIR/" "$PACKAGE_DIR/"

echo "[syntax-lower-bound] pinning SwiftSyntax $LOWER (range $LOWER...$UPPER)"
# SwiftPM can pin a dependency only after the copy has a resolved workspace.
swift package --package-path "$PACKAGE_DIR" resolve
swift package --package-path "$PACKAGE_DIR" resolve swift-syntax --version "$LOWER"

resolved="$(python3 - "$PACKAGE_DIR/Package.resolved" <<'PY'
import json
import sys

pins = json.load(open(sys.argv[1]))["pins"]
versions = [pin["state"].get("version") for pin in pins if pin["identity"] == "swift-syntax"]
print(versions[0] if len(versions) == 1 else "")
PY
)"
if [[ "$resolved" != "$LOWER" ]]; then
    echo "[syntax-lower-bound] expected SwiftSyntax $LOWER, resolved '${resolved}'" >&2
    exit 1
fi

swift test --package-path "$PACKAGE_DIR" --no-parallel \
    -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
    --skip InnoDIBuildSupportTests \
    --skip 'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'

echo "[syntax-lower-bound] SwiftSyntax $LOWER passed the in-process contracts"
