#!/usr/bin/env bash
# CI guard: macro-synthesized accessors must not embed `fatalError(...)`
# traps into user code. Two sites are explicitly allow-listed because
# they are runtime invariants outside the macro's control:
#
#   1. DIContainerCodeGenerator+Dependency.swift —
#      runtime fallback for `validateDAG: false` containers (user opt-out).
#   2. SyntaxBuilders.swift _InnoDIDeferredCell trap —
#      Lazy/Provider deferred-cell ordering invariant.
#
# Both are documented in docs/internal/fatalerror-inventory.md.
#
# Adding a new fatalError site requires either updating that inventory
# AND extending this allow-list, or — far more likely — emitting a
# `DiagnosticMessage` and returning an empty expansion instead.

set -euo pipefail

cd "$(dirname "$0")/.."

# Collect every `fatalError(` occurrence under Sources/InnoDIMacros/...
matches="$(grep -RIn --include='*.swift' 'fatalError(' Sources/InnoDIMacros/ || true)"

if [ -z "$matches" ]; then
    echo "✅ No fatalError calls found in Sources/InnoDIMacros/ (good)."
    exit 0
fi

# Filter out the two allow-listed lines.
unexpected="$(echo "$matches" | grep -v 'DIContainerCodeGenerator+Dependency.swift:.*validateDAG' | grep -v 'SyntaxBuilders.swift:.*_InnoDIDeferredCell' || true)"

if [ -n "$unexpected" ]; then
    echo "❌ Unexpected fatalError call(s) in Sources/InnoDIMacros/:"
    echo "$unexpected"
    echo ""
    echo "If a new runtime invariant truly belongs here, document it in"
    echo "docs/internal/fatalerror-inventory.md and extend the allow-list"
    echo "in Tools/check-no-fatalerror-in-macros.sh. Otherwise, emit a"
    echo "DiagnosticMessage and return an empty expansion."
    exit 1
fi

echo "✅ All fatalError calls in Sources/InnoDIMacros/ are allow-listed."
