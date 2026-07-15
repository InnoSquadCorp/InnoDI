#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"

ROOT_DIR="$DEFAULT_ROOT"
VERSION=""
COMMIT_SHA=""

usage() {
    cat <<'EOF'
Usage: Tools/validate-release-candidate.sh [--root <path>] --version <semver> --commit-sha <sha>

Validates local release-candidate metadata without creating tags or accessing
the network.

Options:
  --root <path>       Repository root (defaults to the script's repository)
  --version <semver>  Stable, unprefixed semantic version (for example 5.0.0)
  --commit-sha <sha>  Full lowercase 40-character Git commit SHA
  -h, --help          Show this help
EOF
}

fail() {
    echo "error: $*" >&2
    exit 1
}

require_option_value() {
    local option="$1"
    local value="${2:-}"

    if [[ -z "$value" || "$value" == --* ]]; then
        fail "$option requires a value"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            require_option_value "$1" "${2:-}"
            ROOT_DIR="$2"
            shift 2
            ;;
        --root=*)
            ROOT_DIR="${1#*=}"
            [[ -n "$ROOT_DIR" ]] || fail "--root requires a value"
            shift
            ;;
        --version)
            require_option_value "$1" "${2:-}"
            VERSION="$2"
            shift 2
            ;;
        --version=*)
            VERSION="${1#*=}"
            [[ -n "$VERSION" ]] || fail "--version requires a value"
            shift
            ;;
        --commit-sha)
            require_option_value "$1" "${2:-}"
            COMMIT_SHA="$2"
            shift 2
            ;;
        --commit-sha=*)
            COMMIT_SHA="${1#*=}"
            [[ -n "$COMMIT_SHA" ]] || fail "--commit-sha requires a value"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

[[ -n "$VERSION" ]] || fail "--version is required"
[[ -n "$COMMIT_SHA" ]] || fail "--commit-sha is required"
[[ -d "$ROOT_DIR" ]] || fail "repository root does not exist: $ROOT_DIR"
ROOT_DIR="$(cd -- "$ROOT_DIR" && pwd -P)"

STABLE_SEMVER_PATTERN='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
FULL_SHA_PATTERN='^[0-9a-f]{40}$'

[[ "$VERSION" =~ $STABLE_SEMVER_PATTERN ]] || \
    fail "version must be a stable, unprefixed semantic version without leading zeroes: $VERSION"
[[ "$COMMIT_SHA" =~ $FULL_SHA_PATTERN ]] || \
    fail "commit SHA must be exactly 40 lowercase hexadecimal characters"

TAG_REF="refs/tags/$VERSION"
git -C "$ROOT_DIR" check-ref-format "$TAG_REF" >/dev/null 2>&1 || \
    fail "version does not form a valid Git tag ref: $TAG_REF"

if ! ACTUAL_HEAD="$(git -C "$ROOT_DIR" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)"; then
    fail "repository root does not contain a resolvable Git HEAD: $ROOT_DIR"
fi
[[ "$ACTUAL_HEAD" == "$COMMIT_SHA" ]] || \
    fail "commit SHA does not match Git HEAD (expected $COMMIT_SHA, found $ACTUAL_HEAD)"

RELEASING_FILE="$ROOT_DIR/RELEASING.md"
[[ -f "$RELEASING_FILE" ]] || fail "missing release source: $RELEASING_FILE"

EXPECTED_LATEST_LINE="Latest stable public release: \`$VERSION\`"
LATEST_LINE_COUNT="$({ grep -c '^Latest stable public release:' "$RELEASING_FILE" || true; })"
EXACT_LATEST_LINE_COUNT="$({ grep -Fxc "$EXPECTED_LATEST_LINE" "$RELEASING_FILE" || true; })"

[[ "$LATEST_LINE_COUNT" == "1" && "$EXACT_LATEST_LINE_COUNT" == "1" ]] || \
    fail "RELEASING.md must contain exactly one line: $EXPECTED_LATEST_LINE"

UNRELEASED_CANDIDATE_LINE="Current development train: \`$VERSION\` (unreleased)"
if grep -Fqx "$UNRELEASED_CANDIDATE_LINE" "$RELEASING_FILE"; then
    fail "RELEASING.md cannot describe release candidate $VERSION as the current unreleased train"
fi

read -r VERSION_SECTION_COUNT NONEMPTY_VERSION_SECTION_COUNT < <(
    awk -v expected_heading="## $VERSION" '
        $0 == expected_heading {
            section_count++
            in_expected_section = 1
            next
        }
        in_expected_section && /^##[[:space:]]/ {
            in_expected_section = 0
        }
        in_expected_section && /[^[:space:]]/ {
            section_has_content = 1
        }
        END {
            print section_count + 0, section_has_content + 0
        }
    ' "$RELEASING_FILE"
)

[[ "$VERSION_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md must contain exactly one '## $VERSION' section (found $VERSION_SECTION_COUNT)"
[[ "$NONEMPTY_VERSION_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md section '## $VERSION' must be nonempty"

README_FILES=(
    "README.md"
    "README.ko.md"
    "README.ja.md"
    "README.zh-Hans.md"
    "README.de.md"
    "README.es.md"
    "README.ru.md"
)

for readme_name in "${README_FILES[@]}"; do
    readme_path="$ROOT_DIR/$readme_name"
    [[ -f "$readme_path" ]] || fail "missing README variant: $readme_name"

    read -r dependency_count matching_dependency_count < <(
        awk -v version="$VERSION" '
            function inspect_dependency() {
                normalized = dependency
                gsub(/[[:space:]]/, "", normalized)

                if (normalized ~ /\.package\(/ && index(normalized, "InnoDI") > 0) {
                    dependency_count++
                    canonical_url = index(normalized, "url:\"https://github.com/InnoSquadCorp/InnoDI.git\"")
                    matching_version = index(normalized, "from:\"" version "\"")
                    if (canonical_url > 0 && matching_version > 0) {
                        matching_dependency_count++
                    }
                }

                dependency = ""
            }

            !collecting && /\.package[[:space:]]*\(/ {
                collecting = 1
                dependency = $0
            }
            collecting && dependency != $0 {
                dependency = dependency "\n" $0
            }
            collecting && /\)/ {
                inspect_dependency()
                collecting = 0
            }
            END {
                if (collecting) {
                    inspect_dependency()
                }
                print dependency_count + 0, matching_dependency_count + 0
            }
        ' "$readme_path"
    )

    [[ "$dependency_count" == "1" ]] || \
        fail "$readme_name must contain exactly one InnoDI package dependency (found $dependency_count)"
    [[ "$matching_dependency_count" == "1" ]] || \
        fail "$readme_name must use the canonical InnoDI package URL with from: \"$VERSION\""
done

echo "Release candidate metadata validated: version=$VERSION commit=$COMMIT_SHA root=$ROOT_DIR"
