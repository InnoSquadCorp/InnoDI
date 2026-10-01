#!/usr/bin/env bash
# CI guard: the Korean README and the Korean DocC articles must stay
# structurally aligned with their English canonical sources, and the Korean
# README must retain critical public API/diagnostic tokens. The structural
# check compares fence counts and H2 header counts, since exact header text
# legitimately differs across translations. Fence counts and header counts
# must match the English canonical because new sections or examples in
# English signal a need for a parallel translation update.
#
# Every English article in the base DocC catalog must have a `ko.lproj`
# counterpart, and every `ko.lproj/*.md` article with an English counterpart
# gets the same structural comparison. A Korean page without an English
# counterpart is reported and skipped.
#
# The other translations were frozen at 6.0.0 and are now notice pages. Their
# READMEs must keep linking the canonical README and their 6.0.0 translation.
# Their `*.lproj` folders hold only a TranslationNotice page and are never
# compared.
#
# Default mode is strict: differences are reported and the script exits
# non-zero. Set `INNODI_README_SYNC_STRICT=0` to demote failures to
# warnings during a soft-rollout window.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

CANONICAL="README.md"
LOCALIZED=(
    "README.ko.md"
)
NOTICE_PAGES=(
    "README.ja.md"
    "README.zh-Hans.md"
    "README.de.md"
    "README.es.md"
    "README.ru.md"
)

DOCC_CATALOG="Sources/InnoDI/InnoDI.docc"
# Only the Korean DocC mirror is maintained. The frozen ja, zh-Hans, de, es,
# and ru folders are deliberately absent from this list.
LOCALIZED_DOCC_DIRS=(
    "$DOCC_CATALOG/ko.lproj"
)

# These exact Markdown tokens carry public 5.0 diagnostics, namespace
# reservations, and generated-API contracts. Structural parity alone cannot
# catch a translated paragraph that silently drops one of them, so every
# localized README must retain each token while it remains canonical English
# documentation. Intentional renames/removals update this list in the same PR.
# shellcheck disable=SC2016 # Markdown backticks are intentional literal text.
CRITICAL_PARITY_TOKENS=(
    '`provide.conditional-declaration-unsupported`'
    '`provide.duplicate-attribute`'
    '`generated-qualifier.inheritance-unverifiable`'
    '`_storage_`'
    '`_override_`'
    '`_innoDI`'
    '`_InnoDI`'
    '`Swift`'
    '`_Concurrency`'
    '`InnoDI._InnoDISubContainerAccessor`'
    '`featureRoot:`'
    '`featureRoots:`'
    '--root-pruning'
)

STRICT="${INNODI_README_SYNC_STRICT:-1}"

count_swift_fences() {
    grep -cE '^```swift([[:space:]]|$)' "$1" || true
}

count_h2_headers() {
    grep -cE '^## ' "$1" || true
}

drift_count=0

# Reports one localized-contract drift. Strict mode reports it as an error;
# otherwise it is demoted to a warning.
report_drift() {
    local file="$1"
    local message="$2"
    local annotation="error"
    if [[ "$STRICT" != "1" ]]; then
        annotation="warning"
    fi
    echo "::$annotation file=$file::$message"
    drift_count=$((drift_count + 1))
}

# Compares the swift fence and H2 header counts of a localized page with its
# English canonical page.
compare_structure() {
    local file="$1"
    local canonical="$2"
    local fences h2 canonical_fences canonical_h2
    fences=$(count_swift_fences "$file")
    h2=$(count_h2_headers "$file")
    canonical_fences=$(count_swift_fences "$canonical")
    canonical_h2=$(count_h2_headers "$canonical")

    if [[ "$fences" != "$canonical_fences" || "$h2" != "$canonical_h2" ]]; then
        report_drift "$file" "structure drift against $canonical (swift_fences=$fences want=$canonical_fences, h2_headers=$h2 want=$canonical_h2)"
    else
        echo "OK $file: swift_fences=$fences h2_headers=$h2"
    fi
}

canonical_fences=$(count_swift_fences "$CANONICAL")
canonical_h2=$(count_h2_headers "$CANONICAL")

echo "Canonical $CANONICAL: swift_fences=$canonical_fences h2_headers=$canonical_h2"

for token in "${CRITICAL_PARITY_TOKENS[@]}"; do
    if ! grep -Fq -- "$token" "$CANONICAL"; then
        echo "::error file=$CANONICAL::critical parity token is no longer present in the canonical README: $token"
        drift_count=$((drift_count + 1))
    fi
done

for file in "${LOCALIZED[@]}"; do
    if [[ ! -f "$file" ]]; then
        report_drift "$file" "missing localized README"
        continue
    fi

    compare_structure "$file" "$CANONICAL"

    for token in "${CRITICAL_PARITY_TOKENS[@]}"; do
        if ! grep -Fq -- "$token" "$file"; then
            report_drift "$file" "critical API/diagnostic token drift (missing $token)"
        fi
    done
done

for file in "${NOTICE_PAGES[@]}"; do
    frozen_link="https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/$file"
    if [[ ! -f "$file" ]] \
        || ! grep -Fq -- "(README.md)" "$file" \
        || ! grep -Fq -- "$frozen_link" "$file"; then
        report_drift "$file" "translation notice must link README.md and $frozen_link"
    else
        echo "OK $file: notice page"
    fi
done

docc_page_count=0
for localized_dir in "${LOCALIZED_DOCC_DIRS[@]}"; do
    if [[ ! -d "$localized_dir" ]]; then
        report_drift "$localized_dir" "missing localized DocC catalog"
        continue
    fi

    compared=0
    for file in "$localized_dir"/*.md; do
        [[ -f "$file" ]] || continue
        canonical_page="$DOCC_CATALOG/$(basename "$file")"
        if [[ ! -f "$canonical_page" ]]; then
            echo "SKIP $file: no English counterpart in $DOCC_CATALOG"
            continue
        fi
        compare_structure "$file" "$canonical_page"
        compared=$((compared + 1))
    done

    # An empty comparison would pass vacuously, for example after the base
    # catalog moves.
    if [[ "$compared" -eq 0 ]]; then
        report_drift "$localized_dir" "no localized DocC article with an English counterpart was compared"
    fi

    # A new English article cannot ship without its Korean mirror.
    for canonical_page in "$DOCC_CATALOG"/*.md; do
        [[ -f "$canonical_page" ]] || continue
        localized_page="$localized_dir/$(basename "$canonical_page")"
        if [[ ! -f "$localized_page" ]]; then
            report_drift "$localized_page" "missing localized counterpart of $canonical_page"
        fi
    done
    docc_page_count=$((docc_page_count + compared))
done

if [[ "$drift_count" -eq 0 ]]; then
    echo "All localized READMEs and $docc_page_count localized DocC article(s) match the English canonical structure and critical API/diagnostic tokens."
    exit 0
fi

if [[ "$STRICT" == "1" ]]; then
    echo "::error::$drift_count localized documentation contract drift(s) found against the English canonical sources. Re-sync the affected files or set INNODI_README_SYNC_STRICT=0 to demote to a warning during a rollout window."
    exit 1
fi

echo "::warning::$drift_count localized documentation contract drift(s) found against the English canonical sources (strict mode disabled)."
exit 0
