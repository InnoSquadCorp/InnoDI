# Migration Guide

Version-by-version upgrade notes. For full release-time
highlights and breaking-change tables, read
[`RELEASING.md`](https://github.com/InnoSquadCorp/InnoDI/blob/main/RELEASING.md);
this article reorganizes the same information by **what
changes a consumer must make**.

## Overview

| From → To | Change category | Required actions |
|---|---|---|
| 1.x → 2.x | Validation policy hardening | Re-run macro tests; resolve any new diagnostics raised by the stricter validator. |
| 2.x → 3.x | OSS baseline + governance | No code change required. Update internal release tooling to read `RELEASING.md` sections instead of legacy notes. |
| 3.x → 4.0 | Public-contract consolidation | Adopt the new `withNames:`/`with:`/`bindings:` matrix on `@SubContainer`. Stop importing `_LazyCell`. Rename any container member starting with one of the reserved `_storage_` / `_override_sub_` / `_innoDISubBuild_` prefixes. |
| 4.0 → 4.1 | DX hardening | Apply the `sub.prefer-with-over-with-names` Fix-it on every `@SubContainer(... withNames:)` site. Update parsers of the lock-timeout stderr block to read structured fields. |
| 4.1 → 4.2 (planned) | `withNames:` deprecation | The hint diagnostic gets promoted from `.note` to `.warning` plus an `@available(*, deprecated)` annotation. Migrate any remaining `withNames:` usage. |
| 4.x → 5.0 (planned) | `withNames:` removal + `@GenerateMock` | Apply the migrations from RFC 0002. Optionally adopt `@GenerateMock` for protocol-based mocks. |

The rest of this article expands each row in the order users
historically need them: 4.0 → 4.1 first (most consumers), then
the upcoming 4.2 / 5.0 surface, then the older 1.x → 4.0 hops.

---

## 4.0 → 4.1

### `@SubContainer(... withNames:)` — apply the Fix-it

InnoDI 4.1 emits a new note diagnostic
`sub.prefer-with-over-with-names` whenever `@SubContainer` uses
`withNames:` in isolation. The diagnostic ships with a
SwiftSyntax Fix-it that rewrites the labelled argument in place.

```swift
// Before — note diagnostic + Fix-it offered
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer

// After — recommended form
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

The two forms parse to the same internal representation, so the
expansion and runtime behavior are identical. The motivation for
moving to `with:` is type-safety (rename safety in IDE
refactors) and preparing for the 5.0 removal of `withNames:` —
see <doc:0002-subcontainer-wiring-simplification> RFC.

### Lock-timeout stderr format change

The validation coordinator's lock-timeout diagnostic moved from
a one-line message to a structured multi-line block. CI scripts
that grep the previous wording (`Timed out waiting for
validation coordinator lock at '...'`) should switch to the
structured fields:

```
path:        <the lock path>
waited:      <seconds>s
holder pid:  <pid>
holder age:  <seconds>s
boot id:     <id>
```

If you only ever read exit code `1` plus the metrics artifact's
`reasonCodes` array, no change is needed.

### Filesystem safety guard — opt-in for unsafe scratch paths

If your build runs the SPM scratch directory on **NFSv3**,
**SMB**, **CIFS**, **WebDAV**, or some FUSE-based filesystems,
the coordinator now refuses to acquire its lock. Either:

1. Move the scratch path: `swift build --scratch-path /tmp/innodi-cache`
2. Opt-in to the unsafe path: `INNODI_ALLOW_UNSAFE_LOCK=1 swift build`
   (the coordinator still emits a warning so the bypass is
   auditable in CI logs).

Local APFS / HFS+ / ext4 / btrfs / xfs / tmpfs builds need no
change.

### Macro-synthesized `fatalError` traps removed

If you depended on the runtime `fatalError("...")` that
`@Provide(.transient)` used to synthesize for malformed input
(no factory, wildcard parameters, unknown scope), be aware those
traps are gone. The same conditions now produce a build-time
diagnostic plus a Swift compiler "stored property has no initial
value" error from the property whose accessor was dropped.

This was source-incompatible only for callers who relied on the
trap as a runtime gate — which we believe is no one — but is
listed here for completeness.

### `ValidationReasonCode.unsafeFilesystem` (artifact change)

If you parse the validation metrics JSON artifact, add a case
for `unsafe-filesystem`. It appears in the `reasonCodes` array
when the FS guard fail-fasts. No schema bump because the field
is `[String]` and has always been open.

### New operator tools

Two additions that you don't have to use, but might want to:

- `swift run InnoDI-DependencyGraph --diagnose-lock [<scratch-path>]` —
  prints filesystem class, environment overrides, and any
  active/stale lock files with metadata. Runbook for
  `lock-contention-timeout` on CI.
- `Tools/check-no-fatalerror-in-macros.sh` — repository-local
  guard that fails CI if a new `fatalError(...)` slips into the
  macro plugin sources outside the two allow-listed runtime
  invariants.

---

## 4.1 → 4.2 (planned)

This section previews the next release for consumers who want
to start migrating early. **Nothing is removed in 4.2** — only
deprecations.

### `withNames:` becomes a deprecation warning

The `sub.prefer-with-over-with-names` diagnostic will be
promoted from `.note` to `.warning`, and the `withNames:`
parameter on `@SubContainer` will gain
`@available(*, deprecated, message: "Use `with: [\.x]`. See
RFC 0002.")`.

Under `-warnings-as-errors` (which the InnoDI release gate uses)
this will fail builds that still spell `withNames:`. The Fix-it
shipped in 4.1 is the recommended migration path.

### No other breaking changes

4.2 is otherwise a stability release. Bug fixes and
documentation only.

---

## 4.x → 5.0 (planned)

5.0 is the first major release that removes deprecated surface.
Two RFCs land together:

| RFC | What | Effect on consumers |
|---|---|---|
| [0001 — `@GenerateMock`](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0001-macro-mock-generation.md) | New macro | Additive. No migration required. Adoption optional. |
| [0002 — SubContainer wiring simplification](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0002-subcontainer-wiring-simplification.md) | Removes `withNames:` | Apply the Fix-it from 4.1 (or migrate by hand) before upgrading to 5.0. |

If you completed the 4.1 → 4.2 migration, the 4.2 → 5.0 step is
a no-op for `withNames:`.

---

## 3.x → 4.0

Covered in detail in [`RELEASING.md` § 4.0.0](https://github.com/InnoSquadCorp/InnoDI/blob/main/RELEASING.md).
The high-impact items:

- New `@SubContainer` wiring matrix: `with:` / `withNames:` /
  `bindings:` plus the implicit form. Pick exactly one
  spelling per member (the validator now diagnoses conflicts).
- `Lazy<T>` and `Provider<T>` are intentionally non-`Sendable`
  deferred handles that must stay on the container's original
  isolation domain.
- The previously public `_LazyCell<T>` runtime helper is removed.
  The macro now emits a local `_InnoDIDeferredCell<T>` inside
  synthesized initializers; downstream code should not depend on
  either symbol.
- Container members whose names begin with `_storage_`,
  `_override_sub_`, `_innoDISubBuild_`, `_innoDIUnresolvedDependency`,
  `_subBuildCell_`, `_lazyCell_`, or `_lazySelfForSub` are now
  rejected with `container.reserved-name-prefix`. Rename any
  such member.

---

## 2.x → 3.x

Validation tightening only. No public API churn. If you have a
3.x project already passing the validator with no warnings,
upgrading from 2.x requires no code changes — only fixing any
diagnostics the stricter validator now surfaces.

---

## 1.x → 2.x

The earliest archived migration. See git history of `RELEASING.md`
for the contemporary notes. If you're still on 1.x, the
recommended path is to upgrade to 4.1 in one step rather than
incrementally — the diagnostic surface in 4.1 is far more
informative than 1.x or 2.x.

---

## See also

- <doc:lock-safety> — filesystem safety policy and lock-timeout
  diagnostic reference.
- <doc:DiagnosticsGuide> — every diagnostic ID with its cause
  and remediation.
- <doc:Validation> — overall validation pipeline and where
  each diagnostic fires in it.
