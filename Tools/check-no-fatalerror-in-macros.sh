#!/usr/bin/env bash
# CI guard: macro-synthesized accessors must not embed `fatalError(...)`
# traps into user code. Runtime invariant paths call the hidden `_innoDITrap`
# support function in the InnoDI module, keeping direct stdlib trap calls out
# of generated container scope.
#
# Adding a direct fatalError site requires a new design review; malformed user
# input should emit a DiagnosticMessage and return a recovery expansion.

set -euo pipefail

cd "$(dirname "$0")/.."

# Collect every `fatalError(` occurrence under Sources/InnoDIMacros/...
matches="$(rg -n -U --glob '*.swift' 'fatalError\s*\(' Sources/InnoDIMacros/ || true)"

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
