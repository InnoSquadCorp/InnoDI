# RFC 0002 — SubContainer wiring simplification

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-04-26
- **Target release**: 5.0 (deprecation in 4.2.0, removal in 5.0)
- **Supersedes**: parts of `Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md`
  documenting the four-way `@SubContainer` wiring matrix

## Summary

Reduce `@SubContainer` same-name wiring from four spellings (implicit,
`with:`, `withNames:`, `bindings:`) to two by deprecating
`withNames:` in 4.2.0 and removing it in 5.0. The `with:` and
`bindings:` forms continue to cover every wiring shape the four-way
matrix covered today, with no expressive loss.

The hint diagnostic that prepares the deprecation
(`sub.prefer-with-over-with-names`) and its automatic Fix-it
already shipped in 4.1.0; this RFC formalizes the timeline through
5.0 and pins the migration story.

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
| 4.1.0 | Note diagnostic `sub.prefer-with-over-with-names` + automatic Fix-it that rewrites `withNames: [...]` in place. | ✅ shipped |
| 4.2.0 | Promote the diagnostic from `.note` to `.warning`. Add `@available(*, deprecated, message: "Use `with: [\.x]`. See RFC 0002.")` to the `withNames:` overload of the macro. Migrate the InnoDI-internal test fixtures and Examples that intentionally exercise `withNames:` to `with:` so the release-gate `-warnings-as-errors` step keeps passing. | pending |
| 4.2.x | If consumer feedback surfaces unforeseen breakage, leave 4.2 in place and gather data. No changes. | conditional |
| 5.0.0 | Remove the `withNames:` parameter from `@SubContainer`. Delete the parser branch, the `subPreferWithOverWithNames` diagnostic, the `subWithConflictsWithWithNames` diagnostic (no longer reachable), and the related test fixtures. Update DocC and the seven translated READMEs. | pending |

## Migration

For an existing user, the change is a one-line edit per
`@SubContainer` member that uses `withNames:`:

```swift
// 4.0 / 4.1
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer

// 4.2 onward (Fix-it applies this automatically)
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

The InnoDI macro plugin already emits a Fix-it that rewrites the
labelled argument in place (see
`makeSubPreferWithOverWithNamesFixIts` in
`Sources/InnoDIMacros/DIContainerValidator.swift`). IDEs that
honor SwiftSyntax Fix-it metadata will offer a one-click migration.

For users who cannot move to 5.0 immediately, the 4.2.x line will
keep `withNames:` working with a deprecation warning. There is no
plan to back-port the 5.0 removal to 4.x.

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

1. **Should the 4.2 promotion to `.warning` happen as part of the
   4.2.0 GA cut, or as a 4.2.0-rc to give consumers one more
   release to react?**
   The InnoDI maintainers' preference (subject to feedback) is to
   ship the warning in 4.2.0 GA. The Fix-it already lands in 4.1.0,
   so by the time 4.2.0 ships, every consumer with IDE Fix-it
   support has had at least one minor cycle to migrate.

2. **Do we need a separate `@available(*, unavailable)` step in a
   4.3.0 to surface the removal more loudly than a warning?**
   Probably not — the warning + Fix-it should be sufficient. We
   can re-evaluate based on inbound issue reports between 4.1 and
   4.2.

3. **Compatibility plan for downstream RFC 0001 (`@GenerateMock`)
   if both ship in 5.0?**
   The two RFCs are independent: 0001 is purely additive
   (`@GenerateMock` is a new macro), 0002 is purely subtractive
   (`withNames:` parameter removal). They share a release train but
   not a code path. The 5.0 release notes will surface both in one
   migration table.

## Acceptance criteria

For 5.0 release:

1. `grep -RIn 'withNames' Sources/ Examples/ Tests/` returns zero
   matches outside of `docs/` (where the historical reference is
   permitted).
2. The `@SubContainer` macro definition in
   `Sources/InnoDI/InnoDI.swift` no longer accepts `withNames:`.
3. `Sources/InnoDIMacros/DIContainerParser.swift` no longer parses
   `withNames:`.
4. `Sources/InnoDIMacros/Diagnostics.swift` removes
   `subPreferWithOverWithNames`, `subWithConflictsWithWithNames`,
   and the `withNames`-specific branch of
   `subInvalidSameNameWiring`.
5. `Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md` documents two
   spellings (`with:`, `bindings:`) plus the implicit form.
6. The seven translated READMEs are in sync.
7. `MigrationGuide.md` (new) covers 1.x → 5.0 with explicit
   pointers from each release's deprecations to their 5.0
   replacements.

## References

- `Sources/InnoDIMacros/DIContainerValidator.swift` — current
  emission of the prefer-with hint and Fix-it.
- `Sources/InnoDIMacros/DIContainerParser.swift` —
  `extractWithDependencyReferences` parses both forms today.
- `docs/internal/fatalerror-inventory.md` — sibling work item from
  the same P0/P1 hardening track.
- `docs/rfcs/0001-macro-mock-generation.md` — 5.0 release-train
  sibling.
