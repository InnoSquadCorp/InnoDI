# `fatalError` Site Inventory (Macro Codegen)

> **Status**: Draft (P0 deliverable for Item 2.A — fatalError → DiagnosticMessage migration)
> **Created**: 2026-04-26
> **Target**: Track every `fatalError(...)` call site emitted by the macro plugin
> so Phase 2.B can migrate them to `DiagnosticMessage` (compile-time error)
> instead of leaving an unreachable runtime trap in user code.

This document is **internal**. Public-facing diagnostic IDs remain in
`Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md`.

---

## 1. Inventory of generated `fatalError` calls

Each row describes a site where the macro plugin emits a `fatalError(...)`
into the user's compiled code. We classify each site so that Phase 2.B
can decide: **eliminate** (replace with diagnostic + empty expansion),
**downgrade** (replace runtime trap with `precondition`), or **keep**
(genuine runtime invariant outside the macro's control).

| # | File / Line | Trigger | Diagnostic emitted today? | Recommended action | Migration risk |
|---|---|---|---|---|---|
| 1 | `Sources/InnoDIMacros/ProvideMacro.swift:125` | `.transient` scope where `transientDependencyResolutionShouldFail()` returned `true` (a parent validator saw an unresolvable factory parameter, e.g. a closure referencing an unknown member). | The earlier validator phase emits `provide.unresolved-factory-parameter` (✅). | **Likely dead code — eliminate after audit.** The reproduce probe in `ProvideMacroTests.transientWithUnresolvedFactoryParameterEmitsDiagnostic` confirms this branch is **not reached** for the obvious inputs that fire `provideUnresolvedFactoryParameter`; the accessor expansion produces a broken `self.<unknown>` reference instead, which still fails compilation because the diagnostic is at error severity. Phase 2.B should attempt to construct an input that *does* reach line 125 — if no such input exists, delete the branch entirely. | Low — diagnostic is terminal in either case. |
| 2 | `Sources/InnoDIMacros/ProvideMacro.swift:147` | `.transient` scope, async factory closure with **wildcard** parameter (`_:`). | `transient-factory.unnamed-parameters` (✅). | **Eliminate.** Same shape as #1 — diagnostic is at error severity. | Low. |
| 3 | `Sources/InnoDIMacros/ProvideMacro.swift:200` | `.transient` scope, sync factory closure with **wildcard** parameter (`_:`). | `transient-factory.unnamed-parameters` (✅, covered by `transientFactoryClosureWithUnderscoreParameterEmitsDiagnostic` test). | **Eliminate.** Symmetric with #2. | Low. |
| 4 | `Sources/InnoDIMacros/ProvideMacro.swift:244` | `.transient` scope, no `factory:`, no `typeExpr`, no inline initializer. The "I literally have no way to construct this" case. | A *separate* validator path raises `provide.transient-factory-required` for some entry points, but the accessor macro can still be reached without a prior diagnostic when the validator is short-circuited (e.g. partial expansion in an SwiftUI Preview). | **Eliminate (with new validator guard).** Add an unconditional `provide.transient-factory-required` from the accessor macro when no factory source exists, then return `[]`. | Medium — needs to confirm no path produces a successful compile that today relies on the trap being lazy. |
| 5 | `Sources/InnoDIMacros/ProvideMacro.swift:267` | `.none` (the parser could not resolve any scope from the attribute, e.g. malformed `@Provide(...)`). | `provide.unknown-scope` (✅, covered indirectly via `assertMacroExpansionDiagnosticCodes`). | **Eliminate.** The diagnostic is terminal; accessor can return `[]`. | Low. |
| 6 | `Sources/InnoDIMacros/ProvideMacro.swift:319` (`handleCodegenInvariant`) | The codegen helper detected an **internal invariant violation** while building expressions (e.g. an unexpected node kind it can't lower). | `internal.codegen-invariant` (✅). This is an internal bug class. | **Downgrade**, do not eliminate. Replace `fatalErrorGetter` with `[]` so the build *also* fails at the diagnostic, but keep the existing diagnostic at `.error`. The runtime trap is unreachable in valid code paths, but this site exists as a "future-proof" catch-all and removing it entirely would silently produce empty accessors if a new internal bug were to appear. | Medium — needs to keep the diagnostic message identical so external watchers don't churn. |

### Symmetric sites (not in `ProvideMacro.swift`)

| # | File / Line | Trigger | Classification |
|---|---|---|---|
| 7 | `Sources/InnoDIMacros/SyntaxBuilders.swift:248` (`fatalErrorStmt`) | Helper used by site #5. | **Removed** when sites #1–#5 are migrated; currently the only caller is `ProvideMacro.swift:267`. |
| 8 | `Sources/InnoDIMacros/SyntaxBuilders.swift:313` (deferred cell trap) | Generated body of `_InnoDIDeferredCell.resolved` when accessed before the parent container has stored a value. | **Keep.** This is a genuine *runtime* invariant for `Lazy<T>` / `Provider<T>` ordering. The macro cannot statically verify the ordering; the trap is the contract boundary. Do not migrate. |
| 9 | `Sources/InnoDIMacros/DIContainerCodeGenerator+Dependency.swift:193` | Generated fallback for containers declared with `validateDAG: false` when a dependency cannot be looked up at expansion time. | **Keep, but improve message.** This is the explicit user opt-out path: by setting `validateDAG: false` the user has accepted runtime failure as a cost. Phase 2.B should reword the trap to clearly state which override the user must supply. |

### Already-migrated reference

| `Sources/InnoDIMacros/Diagnostics.swift:539` (comment block) | A block comment documenting the deliberate `[]` return strategy used by other sites. **No action.** |

---

## 2. Migration plan summary

After Phase 2.B lands, we expect the following deltas:

| File | Before | After |
|---|---|---|
| `ProvideMacro.swift` (sites 1–5) | 5 × `return [fatalErrorGetter(...)]` | 5 × `return []` (with diagnostic guarantee) |
| `ProvideMacro.swift` (site 6, `handleCodegenInvariant`) | Returns `fatalErrorGetter` | Returns `[]`, keeps diagnostic |
| `SyntaxBuilders.swift` `fatalErrorStmt` (site 7) | Public helper | Removed |
| `SyntaxBuilders.swift` deferred-cell trap (site 8) | Runtime trap | **Unchanged** |
| `DIContainerCodeGenerator+Dependency.swift` (site 9) | Runtime trap | **Unchanged**, message reworded |

### CI guard (added in Phase 2.B)

```
grep -RIn 'fatalError' Sources/InnoDIMacros/ \
  | grep -v 'SyntaxBuilders.swift:.*deferred' \
  | grep -v 'DIContainerCodeGenerator+Dependency.swift:.*validateDAG'
# Should return zero matches.
```

The guard intentionally allow-lists the two "keep" sites by file+pattern.
A drift in those files will require an explicit allow-list edit, which
is the desired forcing function.

---

## 3. Test gap analysis (this PR — Item 2.A)

For each "Eliminate" site, we want a reproduce test that:

1. Asserts the diagnostic IS emitted at the expected `MessageID`
2. Asserts macro expansion **either** emits a `fatalErrorGetter` today **or**
   returns `[]` after migration — both behaviors should keep user-facing
   compilation failing for the same reason

| Site | Existing test | Gap addressed in this PR |
|---|---|---|
| #1 (transient unresolved factory parameter) | partial — covered by `transientFactoryClosureWithUnknownParameterFallsBackToFatalErrorGetter` (line 250 of `ProvideMacroTests.swift`) | Added `transientWithUnresolvedFactoryParameterEmitsDiagnostic` (explicit reproduce). |
| #2 (async transient + wildcard) | none | Added `asyncTransientFactoryClosureWithUnderscoreParameterEmitsDiagnostic`. |
| #3 (sync transient + wildcard) | ✅ `transientFactoryClosureWithUnderscoreParameterEmitsDiagnostic` (no change) | — |
| #4 (transient missing factory) | none | Added `transientMissingFactoryEmitsDiagnostic`. |
| #5 (`.none` unknown scope) | ✅ via `provide.unknown-scope` diagnostic test | — |

After Phase 2.B the assertion target shifts: the diagnostic stays, but
expanded source no longer contains a `fatalError("...")` literal. Tests
should be updated then to assert the negative.

---

## 4. Acceptance criteria for Phase 2.B (the follow-up PR)

1. `grep -RIn 'fatalError' Sources/InnoDIMacros/` returns only sites #8 and #9 (allow-listed).
2. All reproduce tests in this inventory still pass and assert the
   appropriate diagnostic at error severity.
3. New regression tests for site #6 (`handleCodegenInvariant`):
   construct a syntactically-malformed factory expression that triggers
   the internal-invariant path, assert diagnostic is raised, and assert
   the expansion returns no accessor.
4. CI pipeline gains the grep guard.
5. `Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md` adds a callout that
   user code can no longer encounter "InnoDI internal codegen invariant
   violated" as a runtime crash — only as a build error.

---

## Appendix A — site discovery command

```sh
grep -RIn --include='*.swift' 'fatalError' Sources/InnoDIMacros/ Sources/InnoDI/
```

Last verified at `4.0.0` / HEAD `eccf068` (see Repository state below).
Re-run before opening the Phase 2.B PR; if new sites appeared, add rows
to §1 first.

## Appendix B — repository state at inventory time

- Branch: `improve/p0-diagnostics-and-fatalerror-inventory`
- Base: `main` @ `eccf068` ("Merge pull request #32 …")
- Tag of record: `4.0.0`
