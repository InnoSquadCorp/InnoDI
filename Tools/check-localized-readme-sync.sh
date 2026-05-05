#!/usr/bin/env bash
# CI guard: localized READMEs must stay structurally aligned with the
# English canonical (README.md). The check compares fence counts and H2
# header counts, since exact header text legitimately differs across
# translations. Fence counts and header counts must match the English
# canonical because new sections or examples in English signal a need
# for a parallel translation update.
#
# Default mode is advisory: differences are reported and the script exits
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
for file in "${LOCALIZED[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "::warning file=$file::missing localized README"
        drift_count=$((drift_count + 1))
        continue
    fi

    fences=$(count_swift_fences "$file")
    h2=$(count_h2_headers "$file")

    if [[ "$fences" != "$canonical_fences" || "$h2" != "$canonical_h2" ]]; then
        echo "::error file=$file::structure drift (swift_fences=$fences want=$canonical_fences, h2_headers=$h2 want=$canonical_h2)"
        drift_count=$((drift_count + 1))
    else
        echo "OK $file: swift_fences=$fences h2_headers=$h2"
    fi
done

if [[ "$drift_count" -eq 0 ]]; then
    echo "All localized READMEs match the English canonical structure."
    exit 0
fi

if [[ "$STRICT" == "1" ]]; then
    echo "::error::$drift_count localized README(s) drifted from $CANONICAL. Re-sync the affected files or set INNODI_README_SYNC_STRICT=0 to demote to a warning during a rollout window."
    exit 1
fi

echo "::warning::$drift_count localized README(s) drifted from $CANONICAL (strict mode disabled)."
exit 0
