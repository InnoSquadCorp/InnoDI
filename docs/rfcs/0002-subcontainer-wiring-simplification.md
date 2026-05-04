# RFC 0002 — SubContainer wiring simplification

- **Status**: **Deferred** (was Draft; see [Update — 2026-04-26](#update--2026-04-26))
- **Authors**: InnoDI maintainers
- **Created**: 2026-04-26
- **Last updated**: 2026-05-04
- **Target release**: previously planned for 5.0; now deferred until
  the upstream Swift compiler limitation described below is fixed
- **Supersedes**: parts of `Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md`
  documenting the four-way `@SubContainer` wiring matrix

## Update — 2026-04-26

The original 4.1 hint diagnostic and the next step
(4.2 deprecation + 5.0 removal of `withNames:`) were attempted
during the same PR train. That work uncovered two blockers: a
Swift compiler limitation that prevents a clean removal, and an
unstable compiler-plugin diagnostic path for non-essential
top-level remarks.

> When `@SubContainer(... with: [\Type.member])` is stacked with
> another peer macro on the same property (`@DIFeatureRoot`,
> `@DIEnvironmentBridge`, etc.), Swift's type-checker reports
> `circular reference expanding peer macros` because resolving
> the key-path's root type requires the enclosing
> `@DIContainer`'s peer expansion to be complete, which in turn
> reads the same attribute. `withNames: ["member"]` (string-typed)
> sidesteps the cycle because strings need no type resolution.

This is reproducible with both single- and multi-element
key-path arrays, with `bindings:` keypaths, with attribute order
swapped, and with the array elements wrapped via `as [AnyKeyPath]`
casts. Every keypath spelling Swift's parser accepts triggers
the type-checker phase that conflicts with peer macro expansion.

Because of this, every consumer who pairs `@SubContainer` with
`@DIFeatureRoot` (or any other peer macro) currently *must*
write `withNames:`. Removing the parameter would break a
documented usage pattern. The right thing to do is to:

1. Keep `withNames:` available — and document it explicitly as
   the escape hatch for the multi-peer-macro case. Done.
2. Disable the non-essential informational diagnostic for
   `withNames:` after real macro-client builds exposed Swift
   compiler-plugin JSON decoding internal errors for top-level
   remark diagnostics. Documentation continues to recommend `with:`
   where the type-checker accepts it, but supported syntax should
   not produce unstable diagnostics.
3. Park this RFC in `Deferred` status. When the upstream Swift
   compiler ships a fix (a Swift Forums issue is the next step),
   reopen the RFC, draft a new timeline, and resume.

The macro no longer emits a migration hint for `withNames:`. Users
still get documentation guidance toward `with:` for the common
single-peer-macro case where the compiler accepts key paths.

## Summary

This RFC originally proposed reducing `@SubContainer` same-name
wiring from four spellings (implicit, `with:`, `withNames:`,
`bindings:`) to two by deprecating `withNames:` in 4.2.0 and
removing it in 5.0. That timeline is now deferred because stacked
peer-macro sites still require the string-typed escape hatch, and
because the attempted informational diagnostic proved unstable in
real macro-client builds.

The current guidance is conservative: prefer `with:` where Swift's
type-checker accepts key paths, keep `withNames:` for stacked
peer-macro contexts, and do not emit migration diagnostics for
supported syntax.

## Motivation

Today a user writing `@SubContainer` chooses between four wiring
labels:

| Form | Example |
|---|---|
| Implicit | `@SubContainer(scope: .shared)` |
| Key-path subset (`with:`) | `@SubContainer(scope: .shared, with: [\.config])` |
| String subset (`withNames:`) | `@SubContainer(scope: .shared, withNames: ["config"])` |
| Remap (`bindings:`) | `@SubContainer(scope: .shared, bindings: [(child: \.config, parent: \.appConfig)])` |

`with:` and `withNames:` are syntactic siblings — they parse to the
same `WithDependencyReference` set internally, generate identical
expansions, and have identical runtime semantics. The duplication
exists for historical reasons: `withNames:` predates the macro's
ability to extract names from key-path syntax. Maintaining both
spellings carries continuing cost:

1. **DX cost**: every consumer learning `@SubContainer` must read
   the four-way matrix to understand which spelling to pick. The
   answer is "always `with:` unless you need remapping (`bindings:`)
   or you can rely on the parent's same-name member shape
   (implicit)."
2. **Maintenance cost**: PR #31 and PR #32 both included rounds of
   `withNames:`-specific hardening (conflicting same-name wiring,
   unparseable wiring, validate-like-`with`). Each new
   constraint we apply to `with:` requires a parallel
   `withNames:` change. Recent history shows the matrix is a
   regression vector.
3. **Type-safety cost**: `withNames:` is typed as `[String]`; if the
   parent member is renamed, the string literal silently breaks at
   build time rather than failing the rename in IDE refactor
   tools. `with:` does not have this issue.

`bindings:` is orthogonal and stays — it is the only spelling that
expresses cross-name (`child.foo` ← `parent.bar`) wiring.

## Non-goals

- Removing `bindings:`. It covers a wiring shape `with:` cannot.
- Removing the implicit (no-args) form. It is the most common case
  and adds no surface area.
- Changing `@SubContainer` scope semantics (`.shared` /
  `.transient`). Those are RFC 0003 territory if we ever revisit.
- Renaming `with:` itself. Stable.

## Proposed timeline

| Release | Action | Already shipped? |
|---|---|---|
| 4.1.x | Keep both `with:` and `withNames:`. Prefer `with:` in documentation where key paths type-check, but do not emit a migration diagnostic. | active |
| Future Swift fix | Re-test stacked peer-macro key-path expansion after the upstream compiler limitation is fixed. | pending |
| Future major | If key paths work in stacked peer-macro contexts and user feedback supports it, draft a new deprecation/removal timeline. | deferred |

## Migration

There is no required migration for existing users. For new
single-peer-macro sites where Swift accepts key paths, prefer
`with:`:

```swift
// Supported, and required for stacked peer-macro escape-hatch cases
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer

// Preferred where key paths type-check
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

The InnoDI macro plugin intentionally does not emit a warning,
remark, or Fix-It for `withNames:` while this RFC is deferred.

## Alternatives considered

### A. Keep both forms forever

Status quo. Rejected because the matrix-of-four DX cost is
permanent and the parser-side hardening cost is ongoing. The
expressive value of `withNames:` is zero (it is a strict subset of
`with:`).

### B. Rename `withNames:` to `withParentNames:` for clarity

Rejected. Renaming does not solve the type-safety problem — the
form is still `[String]` — and it adds a churn step for consumers
without a corresponding benefit.

### C. Delete `withNames:` directly in 4.2 (no deprecation)

Rejected. SemVer-friendly OSS libraries don't break public macro
arguments inside a minor release. The cost of a deprecation cycle
is small (one extra release) compared to the user trust cost of
a surprise breaking change.

### D. Lower `with:` to `withNames:` semantics (string-typed)

Rejected. It would erase rename safety and IDE autocomplete for
every existing user. The opposite of the desired direction.

## Open questions

1. **What upstream Swift compiler change would make key-path wiring
   viable in stacked peer-macro contexts?**
   The likely path is a compiler fix that lets peer-macro expansion
   and key-path root type-checking avoid the current circular
   dependency. This RFC should stay deferred until that behavior is
   observable in a stable toolchain.

2. **Can a future diagnostic be emitted without triggering
   compiler-plugin IPC instability?**
   Any renewed diagnostic should be validated in real macro-client
   targets, not only snapshot expansion tests, because the previous
   top-level informational diagnostic exposed JSON decoding internal
   errors during ordinary builds.

3. **Compatibility plan for downstream RFC 0001 (`@GenerateMock`)
   if both ship in 5.0?**
   The two RFCs are independent: 0001 is purely additive
   (`@GenerateMock` is a new macro), 0002 is purely subtractive
   (`withNames:` parameter removal). They share a release train but
   not a code path. The 5.0 release notes will surface both in one
   migration table.

## Acceptance criteria

Before reopening a deprecation/removal plan:

1. `grep -RIn 'withNames' Sources/ Examples/ Tests/` returns zero
   matches outside of `docs/` (where the historical reference is
   permitted).
2. Real macro-client build targets that currently use stacked
   `@SubContainer` + `@DIFeatureRoot` / `@DIEnvironmentBridge`
   compile successfully with `with:` key paths.
3. Any proposed diagnostic is validated with `swift build` /
   `swift test` on real client targets and does not emit Swift
   compiler-plugin JSON decoding internal errors.
4. The `@SubContainer` macro definition in
   `Sources/InnoDI/InnoDI.swift` no longer accepts `withNames:`.
5. `Sources/InnoDIMacros/DIContainerParser.swift` no longer parses
   `withNames:`.
6. `Sources/InnoDIMacros/Diagnostics.swift` removes
   `subWithConflictsWithWithNames`,
   and the `withNames`-specific branch of
   `subInvalidSameNameWiring`.
7. `Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md` documents two
   spellings (`with:`, `bindings:`) plus the implicit form.
8. The seven translated READMEs are in sync.
9. `MigrationGuide.md` covers 1.x → 5.0 with explicit
   pointers from each release's deprecations to their 5.0
   replacements.

## References

- `Sources/InnoDIMacros/DIContainerValidator.swift` — current
  validation for mutually exclusive `with:` / `withNames:` wiring.
- `Sources/InnoDIMacros/DIContainerParser.swift` —
  `extractWithDependencyReferences` parses both forms today.
- `docs/internal/fatalerror-inventory.md` — sibling work item from
  the same P0/P1 hardening track.
- `docs/rfcs/0001-macro-mock-generation.md` — 5.0 release-train
  sibling.
