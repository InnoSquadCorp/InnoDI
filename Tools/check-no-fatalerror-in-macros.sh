#!/usr/bin/env bash
# CI guard: macro-synthesized accessors must not embed `fatalError(...)`
# traps into user code. Runtime invariant paths call the hidden `_innoDITrap`
# support function in the InnoDI module, keeping direct stdlib trap calls out
# of generated container scope.
#
# Adding a direct fatalError site requires a new design review; malformed user
# input should emit a DiagnosticMessage and return a recovery expansion.

set -euo pipefail

root_dir="$(cd "$(dirname "$0")/.." && pwd)"
if [ "${1:-}" = "--root" ]; then
    if [ -z "${2:-}" ] || [ -n "${3:-}" ]; then
        echo "Usage: $0 [--root <package-root>]" >&2
        exit 2
    fi
    root_dir="$2"
elif [ "$#" -ne 0 ]; then
    echo "Usage: $0 [--root <package-root>]" >&2
    exit 2
fi

cd "$root_dir"

# Collect every `fatalError(` occurrence under Sources/InnoDIMacros/...
if command -v rg >/dev/null 2>&1; then
    if matches="$(rg -n -U --glob '*.swift' 'fatalError\s*\(' Sources/InnoDIMacros/)"; then
        :
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            echo "❌ Failed to scan Sources/InnoDIMacros/ with rg (exit $status)." >&2
            exit 2
        fi
        matches=""
    fi
else
    if matches="$(grep -R -n -E --include='*.swift' 'fatalError[[:space:]]*\(' Sources/InnoDIMacros/)"; then
        :
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            echo "❌ Failed to scan Sources/InnoDIMacros/ with grep (exit $status)." >&2
            exit 2
        fi
        matches=""
    fi
fi

if [ -z "$matches" ]; then
    echo "✅ No fatalError calls found in Sources/InnoDIMacros/ (good)."
    exit 0
fi

echo "❌ Unexpected fatalError call(s) in Sources/InnoDIMacros/:"
echo "$matches"
echo ""
echo "Route runtime invariants through _innoDITrap. For malformed user input,"
echo "emit a DiagnosticMessage and return a recovery expansion."
exit 1
