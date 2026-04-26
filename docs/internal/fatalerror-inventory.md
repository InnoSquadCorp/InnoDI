# `fatalError` Site Inventory (Macro Codegen)

> **Status**: 4.1.0 release gate aligned — macro-synthesized accessor traps
> removed, runtime invariant traps allow-listed, PR and tag release gates both
> run the guard.
> **Created**: 2026-04-26
> **Last updated**: 2026-04-26
> **Target**: Track every `fatalError(...)` call site in the macro package and
> explain which sites are intentionally allowed.

This document is **internal**. Public-facing diagnostic IDs remain in
`Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md`.

---

## Current policy

Macro expansion paths that reject malformed user input must emit diagnostics
and return an empty expansion. They must not synthesize a runtime
`fatalError(...)` accessor into user code.

Two runtime invariant sites remain allow-listed:

| Site | File | Why it remains |
|---|---|---|
| Deferred cell trap | `Sources/InnoDIMacros/SyntaxBuilders.swift` | Generated body of `_InnoDIDeferredCell.resolved` when a deferred dependency is accessed before initialization. This is a runtime contract boundary for `Lazy<T>` / `Provider<T>` ordering. |
| `validateDAG: false` unresolved dependency trap | `Sources/InnoDIMacros/DIContainerCodeGenerator+Dependency.swift` | Explicit user opt-out path. With graph-derived validation disabled, unresolved dependencies may be deferred to runtime and fail with an actionable message. |

All other `fatalError(...)` occurrences under `Sources/InnoDIMacros/` are
unexpected and should fail CI.

---

## Migrated sites

The 4.1.0 macro hardening pass migrated the previously synthesized
`fatalErrorGetter` accessors in `ProvideMacro`:

| Site | Trigger | 4.1.0 behavior |
|---|---|---|
| Transient unresolved factory / `with:` dependency | An unresolvable dependency or factory parameter would previously generate a trapping accessor. | Emits the existing terminal diagnostic and returns `[]`. |
| Async transient factory with wildcard parameter | `@Provide(.transient, asyncFactory: { (_: T) in ... })`. | Emits `transient-factory.unnamed-parameters` and returns `[]`. |
| Sync transient factory with wildcard parameter | `@Provide(.transient, factory: { (_: T) in ... })`. | Emits `transient-factory.unnamed-parameters` and returns `[]`. |
| Transient missing construction source | `.transient` without a factory, type expression, or inline initializer. | Emits `provide.transient-factory-required` and returns `[]`. |
| Unknown scope | Malformed `@Provide(...)` scope that cannot resolve to a supported `DIScope`. | Emits `provide.unknown-scope` and returns `[]`. |
| Internal codegen invariant | Contributor bug path in expression lowering. | Emits `internal.codegen-invariant` and returns `[]`; no runtime trap is synthesized. |

`Sources/InnoDIMacros/SyntaxBuilders.swift` no longer exposes
`fatalErrorStmt`; the helper only existed to build the removed accessors.

---

## CI guard

The repository-local guard is:

```sh
Tools/check-no-fatalerror-in-macros.sh
```

The guard scans `Sources/InnoDIMacros/` for `fatalError(` and allow-lists only
the two runtime invariant sites above. It now runs in both:

- `.github/workflows/macro-tests.yml` for PRs
- `.github/workflows/release.yml` for tag release gates and manual release
  validation

Adding a new runtime trap requires updating this inventory and the guard's
allow-list in the same change.

---

## Verification

Last local verification on 2026-04-26:

```sh
Tools/check-no-fatalerror-in-macros.sh
```

Result: passed; only the two allow-listed runtime invariant sites were present
under `Sources/InnoDIMacros/`.
