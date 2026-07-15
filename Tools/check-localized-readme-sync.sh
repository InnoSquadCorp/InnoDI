#!/usr/bin/env bash
# CI guard: localized READMEs must stay structurally aligned with the English
# canonical (README.md) and retain critical public API/diagnostic tokens. The
# structural check compares fence counts and H2 header counts, since exact
# header text legitimately differs across translations. Fence counts and
# header counts must match the English canonical because new sections or
# examples in English signal a need for a parallel translation update.
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
    "README.ja.md"
    "README.zh-Hans.md"
    "README.de.md"
    "README.es.md"
    "README.ru.md"
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

canonical_fences=$(count_swift_fences "$CANONICAL")
canonical_h2=$(count_h2_headers "$CANONICAL")

echo "Canonical $CANONICAL: swift_fences=$canonical_fences h2_headers=$canonical_h2"

drift_count=0
for token in "${CRITICAL_PARITY_TOKENS[@]}"; do
    if ! grep -Fq -- "$token" "$CANONICAL"; then
        echo "::error file=$CANONICAL::critical parity token is no longer present in the canonical README: $token"
        drift_count=$((drift_count + 1))
    fi
done

for file in "${LOCALIZED[@]}"; do
    if [[ ! -f "$file" ]]; then
        annotation="error"
        if [[ "$STRICT" != "1" ]]; then
            annotation="warning"
        fi
        echo "::$annotation file=$file::missing localized README"
        drift_count=$((drift_count + 1))
        continue
    fi

    fences=$(count_swift_fences "$file")
    h2=$(count_h2_headers "$file")

    if [[ "$fences" != "$canonical_fences" || "$h2" != "$canonical_h2" ]]; then
        annotation="error"
        if [[ "$STRICT" != "1" ]]; then
            annotation="warning"
        fi
        echo "::$annotation file=$file::structure drift (swift_fences=$fences want=$canonical_fences, h2_headers=$h2 want=$canonical_h2)"
        drift_count=$((drift_count + 1))
    else
        echo "OK $file: swift_fences=$fences h2_headers=$h2"
    fi

    for token in "${CRITICAL_PARITY_TOKENS[@]}"; do
        if ! grep -Fq -- "$token" "$file"; then
            annotation="error"
            if [[ "$STRICT" != "1" ]]; then
                annotation="warning"
            fi
            echo "::$annotation file=$file::critical API/diagnostic token drift (missing $token)"
            drift_count=$((drift_count + 1))
        fi
    done
done

if [[ "$drift_count" -eq 0 ]]; then
    echo "All localized READMEs match the English canonical structure and critical API/diagnostic tokens."
    exit 0
fi

if [[ "$STRICT" == "1" ]]; then
    echo "::error::$drift_count localized README contract drift(s) found against $CANONICAL. Re-sync the affected files or set INNODI_README_SYNC_STRICT=0 to demote to a warning during a rollout window."
    exit 1
fi

echo "::warning::$drift_count localized README contract drift(s) found against $CANONICAL (strict mode disabled)."
exit 0
