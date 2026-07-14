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
| 4.0 → 4.1 | DX hardening | No `@SubContainer(... withNames:)` migration is required. Continue using `withNames:` in stacked peer-macro contexts and prefer `with:` for new single-macro sites where Swift's type-checker accepts key paths. Update parsers of the lock-timeout stderr block to read structured fields. |
| 4.1 → 4.2 | `@SubContainer` wiring simplification | Replace every `withNames:` site with `with:` key paths or split stacked peer-macro helper generation into manual/root helper code. `withNames:` is no longer accepted by the public macro signature. |
| 4.2 → 4.3 | Feature-root helper integration | Move new SwiftUI feature root helpers from stacked `@DIFeatureRoot` usage into `@SubContainer(featureRoot:)` or `featureRoots:`. `@DIFeatureRoot` remains deprecated for compatibility. |
| 4.x → 4.x+1 (experimental) | `@GenerateMock` opt-in | RFC 0001 stage 1-3 ship as **experimental** — the attribute is stable, the generated mock shape may evolve. Adoption is opt-in. See <doc:AutoMock>. |
| 4.x → 5.0 (planned) | Contract hardening | Remove `concrete:` and deprecated `@DIFeatureRoot`; adopt the supported declaration matrix, actor-correct access, and graph JSON schema v2. `@GenerateMock` remains experimental until its independent GA criteria pass. |

The rest of this article expands each row in the order users
historically need them: the 4.1 → 4.2 wiring simplification first, then 4.0
→ 4.1 operational hardening, then the upcoming 5.0 surface and older hops.

---

## 4.2 → 4.3

### Feature-root helpers move into `@SubContainer`

```swift
// Before
@SubContainer(scope: .shared, with: [\.config])
@DIFeatureRoot(DashboardRootView.self)
@DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
var dashboard: DashboardContainer

// After
@SubContainer(
    scope: .shared,
    with: [\.config],
    featureRoots: [
        FeatureRoot(DashboardRootView.self),
        FeatureRoot(DashboardShellView.self, as: "dashboardShell")
    ]
)
var dashboard: DashboardContainer
```

For the common single-root case, prefer the shorter form:

```swift
@SubContainer(scope: .shared, with: [\.config], featureRoot: DashboardRootView.self)
var dashboard: DashboardContainer
```

The generated helper names are unchanged: the default root still emits
`dashboardRootView()`, and an alias such as `"dashboardShell"` emits
`dashboardShellRootView()`. The difference is ownership: helper generation now
belongs to the `@DIContainer` member expansion, so `@SubContainer` no longer
needs to be stacked with another peer macro on the same property.

`@DIFeatureRoot` remains available as a deprecated compatibility macro. Keep it
only while migrating existing call sites; new code should use
`featureRoot:` / `featureRoots:`.

---

## Internal v1-v3 adopters moving to 4.x

Teams that adopted early InnoDI builds inside an InnoSquad or Banksalad-style
monorepo should treat 4.x as a validation and public-contract migration, not
only a package-version bump.

Recommended order:

1. Add the 4.x package dependency and build one target without the DAG plugin.
2. Fix macro diagnostics first: reserved generated prefixes, missing factories,
   concrete opt-ins, and custom `init` declarations inside container types.
3. Migrate nested container wiring to `with:` or `bindings:` before enabling the
   hierarchy validator.
4. Enable `InnoDIDAGValidationPlugin` on the target and move `--scratch-path`
   to a local disk if derived data lives on a shared volume.
5. Add `Tools/check-docs-code-blocks.sh` and strict-concurrency tests to the
   repo gate so local examples and internal tutorials do not drift.

Do not migrate by wrapping InnoDI in a runtime service locator. That preserves
old call sites but removes the reviewability and graph validation that make the
4.x line worth adopting. See <doc:AntiPatterns> for boundary examples.

---

## 4.1 → 4.2

### `@SubContainer(... withNames:)` removed

```swift
// Before
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer

// After
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

`withNames:` is no longer present in the public `@SubContainer` signature,
the macro parser, or build-support hierarchy validation. Most sites should
move directly to `with:` because it gives key-path autocompletion and rename
safety in IDE refactors.

If a property previously stacked `@SubContainer` with another peer macro and
used `withNames:` to avoid Swift's key-path circular reference limitation,
split that helper generation instead of keeping the string escape hatch. For
example, keep `@SubContainer(scope:with:)` on the container member and add a
small extension method that constructs the root view from the generated child
container.

`bindings:` remains the explicit child-label to parent-member remapping form,
and `with: []` remains the explicit empty same-name subset that emits
`Child()`.

### Validation plugin state directory

The DAG validation build plugin now stores its lock/cache state under
SwiftPM's `pluginWorkDirectoryURL` instead of `<package>/.build`. This keeps
state off unsafe package-root filesystems when callers move the SwiftPM
scratch path with `swift build --scratch-path /tmp/innodi-cache`.

For lock diagnostics, pass the scratch/plugin state directory you want to
inspect to `swift run InnoDI-DependencyGraph --diagnose-lock <path>`.

### Documentation snippet gate

Release and PR gates now run `Tools/check-docs-code-blocks.sh`. Only Swift
fenced blocks immediately preceded by `<!-- innodi:compile -->` are compiled,
so illustrative snippets stay unmarked while contract snippets fail CI when
they drift.

---

## 4.0 → 4.1

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

5.0 restores the compiler and graph contracts before adding more macro
surface. The originally paired wiring simplification has already landed, and
experimental features do not automatically become GA because this is a major
release.

| Area | Planned consumer effect |
|---|---|
| `concrete:` | Delete the argument. The declared property type determines concrete versus existential storage. |
| `@DIFeatureRoot` | Replace it with `@SubContainer(featureRoot:)` or `featureRoots:`. |
| Declaration kinds | Use file-scope or nominally nested non-generic structs for 5.0 containers/components; unsupported kinds and local scopes receive dedicated diagnostics. |
| `@Provide` declaration | Keep exactly one `@Provide` on a direct, plain, stored instance `var` in its supported `@DIContainer`. Remove duplicate provider attributes, `let`, computed/observed accessors, storage modifiers, property wrappers, conditional/unknown attributes, setter access controls, all source-written property-level actor attributes (including `@MainActor`), standalone, and indirectly nested uses. Request isolation with `@DIContainer(mainActor: true)` and never attach `_InnoDIProvideAccessor` manually. |
| Provider type | Replace opaque `some Protocol` with existential `any Protocol`. Replace implicitly unwrapped `T!` with explicit `T` or `T?`. |
| Function-valued `.input` | Generated initializer parameters remain eager `T` values, so `try` / `await` argument evaluation is unchanged. Direct non-optional function types are detected automatically. Add literal `escaping: true` when a non-optional function type is hidden behind a typealias; the option is invalid outside `.input`. |
| Construction source | A `.shared`/`.transient` member must have exactly one of `factory:`, `asyncFactory:`, `Type.self`, or a property initializer. An `.input` member must have none and cannot use `with:`. |
| Sibling wiring | Use named parameters on the root `factory:`/`asyncFactory:` closure literal, or `Type.self` with a literal array containing only canonical direct-member key paths such as `[\Self.config]` (or `[]`). Named/module/typealias roots, nested components, optional chaining, subscripts, and computed elements are rejected. `with:` supports synchronous providers only. Non-closure factories and property initializers are zero-edge sources and cannot read sibling members. |
| Factory effects | Declare async and throwing effects explicitly. Effect compatibility remains enforced with `validateDAG: false`; `Type.self`/`with:` remains synchronous-only. |
| MainActor | Put dependency conformers, construction, and use of non-`Sendable` generated values for `mainActor: true` components on `@MainActor`. From off actor, construct and consume them inside `MainActor.run`; use direct `await` only when the isolated operation returns a `Sendable` result. Override-application closures for convenience initializers, `withOverrides`, child overrides, and component mounting are now `@MainActor`. |
| Non-main-actor async `withOverrides` | Generated `async` / `async throws` methods and operation closure types are `nonisolated(nonsending)`. They retain the caller's actor executor, so arbitrary non-`Sendable` containers and closures stay within the caller's isolation. Sync overloads are unchanged. |
| Validation | Replace dynamic scope expressions, conditional provider attributes, and complete `@Provide` member declarations inside `#if` with supported, statically analyzable forms. |
| Graph JSON | Migrate consumers to schema v2 module-qualified IDs and explicit target/root-pruning scope. |
| `@GenerateMock` | Remains experimental; no migration or GA freeze is implied by 5.0. |

5.0 splits the component mounting marker by isolation. Ordinary components
continue to conform to `_InnoDIComponentMountable`; components whose container
uses `mainActor: true` instead conform to
`_InnoDIMainActorComponentMountable`. Update generic mounting helpers with a
separate `@MainActor` actor-marker overload and type its override parameter as
`@MainActor (inout Component._InnoDIComponentOverrides) -> Void`. A helper that
only constrains `_InnoDIComponentMountable` no longer accepts a main-actor
component. Keep a non-`Sendable` mounted result inside the `@MainActor` caller
or the `MainActor.run` block instead of returning it to an off-actor context.

For containers without `mainActor: true`, keep asynchronous `withOverrides`
work on the caller's isolation. The generated `async` and `async throws`
methods, including their operation closure types, use
`nonisolated(nonsending)`: they retain the caller's actor executor instead of
requiring the container or closure to cross an isolation boundary. Do not add
`Sendable` merely to satisfy this call path. The synchronous overloads are
unchanged, while every `mainActor: true` overload remains `@MainActor`.

Convert class, actor, enum, protocol, extension, and generic container
declarations to non-generic struct boundaries before adopting 5.0. The same
boundary applies to a stacked `@DIComponent`. Preserve runtime or type-specific
state as an explicit protocol dependency or `.input` value instead of putting
that state on the container declaration itself. A container nested inside a
generic nominal declaration is generic for this policy even when the nested
declaration does not spell its own type parameters. Declarations nested inside
extensions must also move to file scope or a non-generic nominal declaration
because an attached syntax macro cannot prove the genericity of an extension's
target. Containers in executable scopes—including functions, closures,
initializers, accessors, switch cases, and local blocks—must move to file scope
or a non-generic nominal declaration regardless of whether that scope is
generic. Swift may add its own language diagnostic for an inherently invalid
placement such as a type nested in a generic function or a local container
stacked with an attached-extension macro such as `@DIComponent`.

Move every provider to a plain stored instance variable:

```swift
// Before: observed/static/accessor-backed provider declarations are unsupported.
@Provide(.shared, factory: Service(), concrete: true)
static var service: Service {
    didSet { audit(service) }
}

// After
@Provide(.shared, factory: Service(), concrete: true)
var service: Service
```

Do not attach `_InnoDIProvideAccessor` yourself. It is internal accessor
support synthesized by the container macro for valid provider members.
Keep only one `@Provide` attribute per property. A deliberately forged
combination of the compiler-support accessor with another property wrapper can
also receive Swift structural diagnostics in addition to the stable InnoDI
misuse diagnostic.

Remove property wrappers, conditional or unknown attributes, setter access
modifiers such as `private(set)`, and every source-written property-level
global-actor attribute from provider declarations. This includes `@MainActor`:
request isolation with `@DIContainer(mainActor: true)` instead. An
isolation attribute InnoDI generates on the provider declaration or accessor
is internal compiler support. Move a complete provider member out of `#if`;
branch inside its factory or injected implementation instead.

Normalize provider property types before relying on generated storage:

```swift
// Before: opaque and implicitly unwrapped provider types are unsupported.
@Provide(.shared, factory: LiveService())
var service: some ServiceProtocol

@Provide(.input)
var delegate: ServiceDelegate!

// After
@Provide(.shared, factory: LiveService())
var service: any ServiceProtocol

@Provide(.input)
var delegate: ServiceDelegate?

typealias Handler = @Sendable () -> Void

// A direct function spelling is automatic; an alias needs the explicit opt-in.
@Provide(.input, escaping: true)
var handler: Handler
```

Input initializer parameters are still eager values of the declared type.
Callers can continue to pass `throwingValue: try makeValue()` and
`asyncValue: await makeValue()`; Swift evaluates those expressions before the
initializer call. `escaping:` must be a literal Boolean and applies only to a
non-optional function-valued `.input`. Obvious nonfunction or optional-function
shapes receive `provide.escaping-nonfunction-type`, while other scopes receive
`provide.escaping-invalid-scope`. The macro accepts identifier/member aliases
conservatively, so Swift may add its own diagnostic if an alias marked
`escaping: true` does not resolve to a non-optional function type.

Audit construction sources before rewriting edges. A `.shared` or `.transient`
member must declare exactly one of `factory:`, `asyncFactory:`, `Type.self`, or
a property initializer. An `.input` member declares none of those and cannot
use `with:`. The four sources are alternatives, not additive configuration.

Rewrite every sibling-dependent construction source into one of the two
explicit edge forms:

```swift
@DIContainer
struct FeatureContainer {
    @Provide(.input)
    var apiClient: APIClient

    // Before: opaque zero-edge expression that illegally reads a sibling.
    @Provide(.shared, factory: Repository(client: apiClient), concrete: true)
    var repository: Repository

    // After: the root closure's named parameter declares the sibling edge.
    @Provide(.shared, factory: { (apiClient: APIClient) in
        Repository(client: apiClient)
    }, concrete: true)
    var migratedRepository: Repository
}
```

`Type.self` plus a literal `with:` key-path array remains the explicit
autowiring form. Because the public parameter is `[AnyKeyPath]`, every entry
must use exactly the canonical direct-member spelling `\Self.member`, such as
`with: [\Self.apiClient]`; an empty `with: []` is valid. Named container,
module-qualified, and typealias roots are rejected, as are nested components,
optional chaining, subscripts, and computed elements. This form can reference
only synchronously constructed providers. A non-closure `factory:` expression
or property initializer is allowed only as an opaque zero-edge source; use a
qualified global/static construction symbol so it cannot be mistaken for
sibling wiring.

Effects are not inferred from those edges. Use `asyncFactory:` when a named
root parameter or `with:` key path targets an async provider, and make the
closure `async throws` when the provider can throw. `validateDAG: false` does
not bypass this compatibility matrix. `Type.self`/`with:` is intentionally
stricter and cannot target either `async` or `async throws` providers.

This section is the migration outline while implementation proceeds. Remaining
diagnostics, codemod commands, and before/after examples are release blockers
and will be added before the 5.0.0 tag.

---

## 3.x → 4.0

Covered in detail in [`RELEASING.md` § 4.0.0](https://github.com/InnoSquadCorp/InnoDI/blob/main/RELEASING.md).
The high-impact items:

- New `@SubContainer` wiring matrix at the time: `with:` / `withNames:` /
  `bindings:` plus the implicit form. Current releases accept `with:` /
  `bindings:` only. Pick exactly one
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
