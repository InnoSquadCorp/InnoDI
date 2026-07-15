# `fatalError` Site Inventory (Macro Codegen)

> **Status**: 5.0 hardening aligned — macro-synthesized source contains no
> direct `fatalError(...)` calls; generated invariant paths route through one
> hidden runtime support function in the `InnoDI` module.
> **Created**: 2026-04-26
> **Last updated**: 2026-07-15
> **Target**: Track every `fatalError(...)` call site in the macro package and
> explain which sites are intentionally allowed.

This document is **internal**. Public-facing diagnostic IDs remain in
`Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md`.

---

## Current policy

Macro expansion paths that reject malformed user input must emit diagnostics
and must not synthesize a runtime `fatalError(...)` accessor into user code.
Accessor macros may emit an unreachable non-observing recovery getter when an
empty accessor expansion would make Swift add a secondary structural error;
the primary InnoDI diagnostic must still make the declaration unbuildable.

Two generated runtime invariant paths remain, but neither embeds a direct
stdlib trap call in macro output:

| Site | File | Why it remains |
|---|---|---|
| Deferred cell trap | `Sources/InnoDIMacros/SyntaxBuilders.swift` | Generated body of `_InnoDIDeferredCell.resolve` calls `_innoDITrap` when a deferred dependency is accessed before initialization. This is a runtime contract boundary for `Lazy<T>` / `Provider<T>` ordering. |
| `validateDAG: false` unresolved dependency trap | `Sources/InnoDIMacros/DIContainerCodeGenerator+Dependency.swift` | Explicit user opt-out path. With graph-derived validation disabled, unresolved dependencies call `_innoDITrap` with the dependency name and actionable remediation. |

The single stdlib `fatalError(...)` implementation lives in
`Sources/InnoDI/InnoDI.swift`, outside generated container scope. Its reserved
`_innoDI` name, the generated `InnoDI._innoDITrap` qualification, and the
reserved `InnoDI` names in the container's direct scope and visible enclosing
binders prevent those declarations from shadowing calls emitted by the macro.
Enclosing member lists and declarations elsewhere in a consumer file or module
are outside an attached syntax macro's validation boundary. The target-scoped
full-source preflight planned later in the 5.0 train will own them; until then,
Swift may diagnose those shadowing declarations itself. Diagnostic-only recovery getters use an
identifier-free nonreturning loop instead of a runtime trap. Any
`fatalError(...)` occurrence under `Sources/InnoDIMacros/` is now unexpected
and fails CI.

---

## Migrated sites

The 4.1.0 macro hardening pass migrated the previously synthesized
`fatalErrorGetter` accessors in `ProvideMacro`:

| Site | Trigger | 4.1.0 behavior |
|---|---|---|
| Transient unresolved factory / `with:` dependency | An unresolvable dependency or factory parameter would previously generate a trapping accessor. | The container emits the terminal diagnostic and the generated accessor owner emits an unreachable recovery getter. |
| Async transient factory with wildcard parameter | `@Provide(.transient, asyncFactory: { (_: T) in ... })`. | The container emits `transient-factory.unnamed-parameters` once and the generated accessor owner emits an unreachable recovery getter. |
| Sync transient factory with wildcard parameter | `@Provide(.transient, factory: { (_: T) in ... })`. | The container emits `transient-factory.unnamed-parameters` once and the generated accessor owner emits an unreachable recovery getter. |
| Transient missing construction source | `.transient` without a factory, type expression, or inline initializer. | The container emits `provide.transient-factory-required` once and the generated accessor owner emits an unreachable recovery getter. |
| Unknown scope | Malformed `@Provide(...)` scope that cannot resolve to a supported `DIScope`. | Emits `provide.unknown-scope` and an unreachable recovery getter so Swift does not add a secondary accessor-macro error. |
| Transient dependency validation recovery | A transient factory has an effect-incompatible hard edge, a `Lazy<T>` async target, or an invalid `Provider<T>` target. | The container emits the terminal dependency diagnostic and attaches the internal transient-accessor owner with recovery enabled; its unreachable getter prevents secondary `await` / `try` errors. |
| Ambiguous provider or factory-parameter identity | Duplicate provider names and duplicate `Lazy<T>` / `Provider<T>` closure parameter names previously reached `Dictionary(uniqueKeysWithValues:)`; hard and cross-kind duplicates shared the same ambiguous identity contract. Backtick-escaped managed identifiers could also bypass raw-spelling comparisons and corrupt generated names. | The parser and validator emit stable duplicate/escaped-identity diagnostics, every ambiguous provider receives recovery accessors, escaped SubContainer declarations receive no generated support, and defensive lookup tables preserve the first entry instead of trapping. |
| Internal codegen invariant | Contributor bug path in expression lowering. | Emits `internal.codegen-invariant` and returns `[]`; no runtime trap is synthesized. |

`Sources/InnoDIMacros/SyntaxBuilders.swift` no longer exposes
`fatalErrorStmt`; the helper only existed to build the removed accessors.

---

## CI guard

The repository-local guard is:

```sh
Tools/check-no-fatalerror-in-macros.sh
```

The guard scans `Sources/InnoDIMacros/` with a multiline expression matching
`fatalError`, optional whitespace, and `(`, then rejects every match. It runs
in both:

- `.github/workflows/macro-tests.yml` for PRs
- `.github/workflows/release.yml` for tag release gates and manual release
  validation

Adding a new generated runtime failure path requires updating this inventory
and routing the implementation through `InnoDI._innoDITrap`; the macro-source
guard has no allow-list.

---

## Verification

Last local verification on 2026-07-15:

```sh
Tools/check-no-fatalerror-in-macros.sh
```

Result: passed; no direct `fatalError(...)` call remains under
`Sources/InnoDIMacros/`.
