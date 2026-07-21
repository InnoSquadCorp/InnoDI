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
UNRELEASED_CANDIDATE_LINE="Current development train: \`$VERSION\` (unreleased)"

RELEASE_SECTION_METRICS="$({
    awk \
        -v expected_latest_line="$EXPECTED_LATEST_LINE" \
        -v unreleased_candidate_line="$UNRELEASED_CANDIDATE_LINE" \
        -v expected_heading="## $VERSION" '
        function has_meaningful_content(line, normalized) {
            normalized = line
            sub(/^[[:space:]]+/, "", normalized)
            sub(/[[:space:]]+$/, "", normalized)

            if (normalized == "" ||
                normalized ~ /^<!--.*-->$/ ||
                normalized ~ /^#{1,6}[[:space:]]/ ||
                normalized ~ /^(```|~~~)/ ||
                normalized ~ /^[-*_][-*_[:space:]]*$/) {
                return 0
            }

            sub(/^[-*+][[:space:]]+/, "", normalized)
            sub(/^[0-9]+[.)][[:space:]]+/, "", normalized)
            sub(/^\[[ xX]\][[:space:]]+/, "", normalized)
            gsub(/[[:punct:][:space:]]/, "", normalized)
            normalized = tolower(normalized)

            return normalized != "" &&
                normalized != "ready" &&
                normalized != "releasecandidateisready" &&
                normalized != "tbd" &&
                normalized != "todo" &&
                normalized != "placeholder" &&
                normalized != "comingsoon" &&
                normalized != "none" &&
                normalized != "na" &&
                normalized != "notapplicable" &&
                normalized != "nochanges"
        }

        {
            line = $0
            sub(/\r$/, "", line)

            if (line ~ /^Latest stable public release:/) {
                latest_line_count++
            }
            if (line == expected_latest_line) {
                exact_latest_line_count++
            }
            if (line == unreleased_candidate_line) {
                unreleased_candidate_line_count++
            }
            if (line == "## Unreleased") {
                unreleased_section_count++
            }

            if (line == expected_heading) {
                version_section_count++
                in_expected_section = 1
                active_subsection = ""
                next
            }

            if (line ~ /^##[[:space:]]/) {
                in_expected_section = 0
                active_subsection = ""
                next
            }

            if (!in_expected_section) {
                next
            }

            if (line ~ /[^[:space:]]/) {
                nonempty_version_section_count = 1
            }

            if (line == "### Highlights") {
                highlights_count++
                active_subsection = "highlights"
                next
            }
            if (line == "### Breaking and Behavior Changes" ||
                line == "### Breaking or Behavior Changes") {
                breaking_count++
                active_subsection = "breaking"
                next
            }
            if (line == "### Upgrade Actions") {
                upgrade_count++
                active_subsection = "upgrade"
                next
            }
            if (line ~ /^###[[:space:]]/) {
                active_subsection = ""
                next
            }

            if (!has_meaningful_content(line)) {
                next
            }

            if (active_subsection == "highlights") {
                highlights_has_content = 1
            } else if (active_subsection == "breaking") {
                breaking_has_content = 1
            } else if (active_subsection == "upgrade") {
                upgrade_has_content = 1
            }
        }

        END {
            print latest_line_count + 0,
                exact_latest_line_count + 0,
                unreleased_candidate_line_count + 0,
                unreleased_section_count + 0,
                version_section_count + 0,
                nonempty_version_section_count + 0,
                highlights_count + 0,
                highlights_has_content + 0,
                breaking_count + 0,
                breaking_has_content + 0,
                upgrade_count + 0,
                upgrade_has_content + 0
        }
    ' "$RELEASING_FILE"
})" || fail "failed to inspect release notes in RELEASING.md"

read -r \
    LATEST_LINE_COUNT \
    EXACT_LATEST_LINE_COUNT \
    UNRELEASED_CANDIDATE_LINE_COUNT \
    UNRELEASED_SECTION_COUNT \
    VERSION_SECTION_COUNT \
    NONEMPTY_VERSION_SECTION_COUNT \
    HIGHLIGHTS_SECTION_COUNT \
    HIGHLIGHTS_HAS_CONTENT \
    BREAKING_SECTION_COUNT \
    BREAKING_HAS_CONTENT \
    UPGRADE_SECTION_COUNT \
    UPGRADE_HAS_CONTENT \
    <<< "$RELEASE_SECTION_METRICS"

[[ "$LATEST_LINE_COUNT" == "1" && "$EXACT_LATEST_LINE_COUNT" == "1" ]] || \
    fail "RELEASING.md must contain exactly one line: $EXPECTED_LATEST_LINE"
[[ "$UNRELEASED_CANDIDATE_LINE_COUNT" == "0" ]] || \
    fail "RELEASING.md cannot describe release candidate $VERSION as the current unreleased train"
[[ "$UNRELEASED_SECTION_COUNT" == "0" ]] || \
    fail "RELEASING.md cannot contain a '## Unreleased' section for a release candidate"
[[ "$VERSION_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md must contain exactly one '## $VERSION' section (found $VERSION_SECTION_COUNT)"
[[ "$NONEMPTY_VERSION_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md section '## $VERSION' must be nonempty"
[[ "$HIGHLIGHTS_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md section '## $VERSION' must contain exactly one '### Highlights' subsection (found $HIGHLIGHTS_SECTION_COUNT)"
[[ "$HIGHLIGHTS_HAS_CONTENT" == "1" ]] || \
    fail "RELEASING.md subsection '### Highlights' must contain non-placeholder content"
[[ "$BREAKING_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md section '## $VERSION' must contain exactly one breaking or behavior changes subsection (found $BREAKING_SECTION_COUNT)"
[[ "$BREAKING_HAS_CONTENT" == "1" ]] || \
    fail "RELEASING.md breaking or behavior changes subsection must contain non-placeholder content"
[[ "$UPGRADE_SECTION_COUNT" == "1" ]] || \
    fail "RELEASING.md section '## $VERSION' must contain exactly one '### Upgrade Actions' subsection (found $UPGRADE_SECTION_COUNT)"
[[ "$UPGRADE_HAS_CONTENT" == "1" ]] || \
    fail "RELEASING.md subsection '### Upgrade Actions' must contain non-placeholder content"

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

MAJOR_MINOR_VERSION="${VERSION%.*}"
ENGLISH_MIGRATION_GUIDE="$ROOT_DIR/Sources/InnoDI/InnoDI.docc/MigrationGuide.md"
KOREAN_MIGRATION_GUIDE="$ROOT_DIR/Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md"

[[ -f "$ENGLISH_MIGRATION_GUIDE" ]] || \
    fail "missing migration guide: Sources/InnoDI/InnoDI.docc/MigrationGuide.md"
[[ -f "$KOREAN_MIGRATION_GUIDE" ]] || \
    fail "missing migration guide: Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md"

if awk -v version="$MAJOR_MINOR_VERSION" '
    index($0, version) > 0 && tolower($0) ~ /unreleased/ { found = 1 }
    END { exit(found ? 0 : 1) }
' "$ENGLISH_MIGRATION_GUIDE"; then
    fail "Sources/InnoDI/InnoDI.docc/MigrationGuide.md still describes $MAJOR_MINOR_VERSION as unreleased"
fi

if awk -v version="$MAJOR_MINOR_VERSION" '
    index($0, version) > 0 && index($0, "미출시") > 0 { found = 1 }
    END { exit(found ? 0 : 1) }
' "$KOREAN_MIGRATION_GUIDE"; then
    fail "Sources/InnoDI/InnoDI.docc/ko.lproj/MigrationGuide.md still describes $MAJOR_MINOR_VERSION as 미출시"
fi

echo "Release candidate metadata validated: version=$VERSION commit=$COMMIT_SHA root=$ROOT_DIR"
