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
| 4.0 → 4.1 | DX hardening | Apply the `sub.prefer-with-over-with-names` Fix-it on every `@SubContainer(... withNames:)` site **where Swift's type-checker accepts the keypath form**. See [`withNames:` deferral note](#withnames-deferral-note). Update parsers of the lock-timeout stderr block to read structured fields. |
| 4.x → 5.0 (planned) | `@GenerateMock` only | RFC 0001 lands as planned. The `withNames:` removal originally planned for 5.0 is **deferred** — see RFC 0002. |

The rest of this article expands each row in the order users
historically need them: 4.0 → 4.1 first (most consumers), then
the upcoming 4.2 / 5.0 surface, then the older 1.x → 4.0 hops.

---

## 4.0 → 4.1

### `@SubContainer(... withNames:)` — apply the Fix-it where it works

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
expansion and runtime behavior are identical. Migrating to `with:`
gives you key-path autocompletion and rename safety in IDE
refactors.

#### `withNames:` deferral note

If your `@SubContainer` is **stacked with another peer macro on
the same property** (`@DIFeatureRoot`, `@DIEnvironmentBridge`, …)
and the Swift compiler reports
`circular reference expanding peer macros`, leave that site on
`withNames:`. RFC 0002 is currently in `Deferred` status because
no key-path spelling currently survives this combination. The
hint and Fix-it remain available for the common
single-peer-macro case where the compiler accepts key paths;
they should not be applied to sites that the compiler refuses.

### Lock-timeout stderr format change

The validation coordinator's lock-timeout diagnostic moved from
a one-line message to a structured multi-line block. CI scripts
that grep the previous wording (`Timed out waiting for
validation coordinator lock at '...'`) should switch to the
structured fields:

```text
path:        <the lock path>
waited:      <seconds>s
holder pid:  <pid>
holder age:  <seconds>s
boot id:     <id>
```

If you only ever read exit code `1` plus the metrics artifact's
`reasonCodes` array, no change is needed.

### Filesystem safety guard — opt-in for unsafe scratch paths

If your build runs the SPM scratch directory on **NFS**,
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

## 4.x → 5.0 (planned)

5.0 is the first major release that takes additive RFCs through
to GA. The originally-paired removal RFC is now deferred.

| RFC | What | Effect on consumers |
|---|---|---|
| [0001 — `@GenerateMock`](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0001-macro-mock-generation.md) | New macro | Additive. No migration required. Adoption optional. |
| [0002 — SubContainer wiring simplification](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0002-subcontainer-wiring-simplification.md) | Originally: remove `withNames:` | **Deferred**. The upstream Swift compiler currently rejects the key-path-only form in stacked peer-macro contexts; `withNames:` stays in 5.0 so consumers retain a working spelling. The 4.1 hint + Fix-it stay in place for the common single-peer-macro case where the compiler accepts key paths. |

If your `@SubContainer` sites are **not** stacked with another
peer macro, 5.0 is otherwise a no-op for SubContainer wiring —
the Fix-it from 4.1 should already have moved them to `with:`.

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
