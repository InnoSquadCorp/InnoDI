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
| 4.x → 5.0 | Contract hardening | Remove `concrete:` and deprecated `@DIFeatureRoot`; adopt the supported declaration matrix, actor-correct access, and graph JSON schema v2. `@GenerateMock` remains experimental until its independent GA criteria pass. |

The rest of this article expands each row in the order users
historically need them: the 4.1 → 4.2 wiring simplification first, then 4.0
→ 4.1 operational hardening, then the 5.0 surface and older hops.

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

In 4.3, `@DIFeatureRoot` remained available as a deprecated compatibility
macro. InnoDI 5.0 removes it; migrate every remaining call site to
`featureRoot:` / `featureRoots:` before upgrading.

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
  guard that fails CI if any direct `fatalError(...)` slips into the
  macro plugin sources. Runtime invariant paths use the hidden
  `_innoDITrap` entry point instead.

---

## 5.x → 6.0 vocabulary

The 6.0 source vocabulary separates external inputs from provider lifetime and
makes hierarchy/isolation intent part of `@DIContainer`:

```swift
// Before
@DIComponent
@DIContainer(mainActor: true)
struct FeatureContainer {
    @Provide(.input) var config: FeatureConfig
}

// After
@DIContainerRole(.component, isolation: .mainActor)
struct FeatureContainer {
    @Input var config: FeatureConfig
}
```

Use `@DIContainerRole(.root)` in place of `@DIHierarchyRoot` combined with
`@DIContainer(root: true)`. The compatibility spellings continue to compile
during the 6.0 preparation train. `InnoDI-Migrate --check`, `--report`, and
`--write` apply the new spelling mechanically, preserve `validateDAG` and
`escaping`, and are idempotent. The migrator leaves commented, dynamic, or
conflicting role sites unchanged and emits a blocking diagnostic rather than
guessing intent.

`@Input(.assisted)` records that the value arrives at a child-factory call.
During the 6.0 preparation train, declare a source-visible nested
`@AssistedFactory(...static:...assisted:...) struct AssistedFactory {}` and let
the parent own it with `@SubContainerFactory(Child.self, bindings: ...)`.
Whole-source validation requires every ordinary child input exactly once and
rejects assisted inputs in the static binding list. RFC 0006 remains Draft, so
keep pilot revisions pinned until naming and removal decisions are accepted.

Replace `_InnoDIMultibindingPrototype(members: ["first", "second"])` with a
direct injectable collection declaration:

```swift
@Multibinding([\Self.first, \Self.second])
var services: [any Service]
```

Contributor key-path order is output order. Contributors must be synchronous
direct managed dependencies whose written type exactly matches the array
element type. The collection preserves contributor lifetimes and overrides,
can itself be injected into another provider, and has its own test override.
The SPI remains available only for pinned preparation consumers until RFC 0006
accepts the 6.0 naming and removal decision.

---

## 4.x → 5.0

5.0 restores the compiler and graph contracts before adding more macro
surface. The originally paired wiring simplification has already landed, and
experimental features do not automatically become GA because this is a major
release.

| Area | Consumer effect |
|---|---|
| `concrete:` | Delete the argument. The declared property type determines concrete versus existential storage. |
| `@DIFeatureRoot` | Replace it with `@SubContainer(featureRoot:)` or `featureRoots:`. |
| Declaration kinds | Use file-scope or nominally nested non-generic structs for 5.0 containers/components; unsupported kinds, local scopes, and explicit `private` containers receive dedicated diagnostics. Use `fileprivate` for same-file mounting or a default-access container inside a private namespace. |
| `@Provide` declaration | Keep exactly one `@Provide` on a uniquely named, unescaped, direct, plain, stored instance `var` in its supported `@DIContainer`. Remove duplicate provider attributes or property names, backtick-escaped names, `let`, computed/observed accessors, storage modifiers, property wrappers, conditional/unknown attributes, setter access controls, all source-written property-level actor attributes (including `@MainActor`), standalone, and indirectly nested uses. Request isolation with `@DIContainer(mainActor: true)` and never attach `_InnoDIProvideAccessor` manually. |
| `@SubContainer` declaration | Keep exactly one `@SubContainer` on an unescaped, direct, plain, stored instance `var` in its supported parent `@DIContainer`. Move complete child declarations out of `#if`, remove competing wrappers and storage/accessor modifiers, and never attach `_InnoDISubContainerAccessor` manually. |
| Provider type | Replace opaque `some Protocol` with existential `any Protocol`. Replace implicitly unwrapped `T!` with explicit `T` or `T?`. |
| Function-valued `.input` | Generated initializer parameters remain eager `T` values, so `try` / `await` argument evaluation is unchanged. Direct non-optional function types are detected automatically. Add literal `escaping: true` when a non-optional function type is hidden behind a typealias; the option is invalid outside `.input`. |
| Construction source | A `.shared`/`.transient` member must have exactly one of `factory:`, `asyncFactory:`, `Type.self`, or a property initializer. An `.input` member must have none and cannot use `with:`. |
| Sibling wiring | Use uniquely named, unescaped parameters on the root `factory:`/`asyncFactory:` closure literal, or `Type.self` with a literal array containing only canonical direct-member key paths such as `[\Self.config]` (or `[]`). Duplicate effective names across ordinary, `Lazy<T>`, and `Provider<T>` parameters and all backtick-escaped dependency parameter names are rejected. Named/module/typealias roots, nested components, optional chaining, subscripts, and computed elements are rejected. `with:` supports synchronous providers only. Non-closure factories and property initializers are zero-edge sources and cannot read sibling members. |
| Factory effects | Declare async and throwing effects explicitly. Effect compatibility remains enforced with `validateDAG: false`; `Type.self`/`with:` remains synchronous-only. |
| MainActor | Put dependency conformers, construction, and use of non-`Sendable` generated values for `mainActor: true` components on `@MainActor`. From off actor, construct and consume them inside `MainActor.run`; use direct `await` only when the isolated operation returns a `Sendable` result. Override-application closures for convenience initializers, `withOverrides`, child overrides, and component mounting are now `@MainActor`. |
| Non-main-actor async `withOverrides` | Generated `async` / `async throws` methods and operation closure types are `nonisolated(nonsending)`. They retain the caller's actor executor, so arbitrary non-`Sendable` containers and closures stay within the caller's isolation. Sync overloads are unchanged. |
| Validation | Replace dynamic scope expressions, conditional provider attributes, and complete `@Provide` or `@SubContainer` member declarations inside `#if` with supported, statically analyzable forms. |
| Generated names | Rename direct container declarations beginning with `_storage_`, `_override_`, `_innoDI`, or `_InnoDI`, plus any direct declaration named `InnoDI`, nested type/typealias named `Swift` or `_Concurrency`, and a container, enclosing nominal, or generic parameter named `InnoDI`, `Swift`, or `_Concurrency`. Value members named `Swift` or `_Concurrency` remain available. `@DIEnvironmentBridge` also reserves type-namespace `Swift`, `SwiftUI`, and `InnoDISwiftUI` in its target and visible enclosing binders, supports only struct/class/enum targets, and no longer supports an extension target, a target nested in an extension, or a local target inside executable code. The required target-scoped full-source preflight rejects visible qualifier shadows from sibling files, enclosing members, matching extensions, and imported dependency targets, plus direct-extension and local bridge targets that an attached macro cannot validate alone. Without that preflight, Swift may issue its compiler-owned restriction first for direct-extension or local targets. Former implementation-local spellings such as `_resolved_`, `_task_`, `_lazyCell_`, `_subBuildCell_`, and `_lazySelf` are available again. Public initializer and operation labels are unchanged. |
| Generated peer collisions | Give every direct `@Provide` and `@SubContainer` property a unique name across both roles. Distinct names can still map to the same hidden peer—for example async `X` and `task_X`, or child `X` and `sub_X`, `sub_apply_X`, or `apply_X`. Follow `container.generated-symbol-collision` and rename either declaration; the diagnostic names the exact generated symbol and its first source claim. |
| Graph JSON | Migrate consumers to schema v2 module-qualified IDs and explicit target/root-pruning scope. |
| `@GenerateMock` | Remains experimental; no migration or GA freeze is implied by 5.0. |

If a generated container or bridge is a class, or is nested in one, its first
inherited type must resolve through the target-scoped source snapshot. The
preflight follows source-visible superclass and typealias chains to find
inherited qualifier shadows. SDK-only and binary-only declarations are outside
this conservative syntactic index, so they fail in the same way as unresolved
or ambiguous first inheritance with
`generated-qualifier.inheritance-unverifiable`. Move the generated site to a
struct/enum or a source-visible adapter when that chain cannot be exposed. For
bridge generation, inherited type members named `Swift` or `SwiftUI` must be
renamed; inherited `InnoDISwiftUI` is safe, while direct and enclosing
declarations with that name remain reserved.

Run the public migration executable before compiling the rest of the package:

```bash
swift run InnoDI-Migrate --root . --check
swift run InnoDI-Migrate --root . --report --output migration-report.json
swift run InnoDI-Migrate --root . --write
swift run InnoDI-Migrate --root . --check
```

`--check` exits with `1` and prints one `MIGRATE` record per file when safe
rewrites are pending. `--report` performs the same read-only preflight and emits
a deterministic schema-v1 JSON inventory to standard output, or atomically to
the path supplied with `--output`. The report contains relative paths, stable
codes, counts, status, and diagnostic messages, but never original or migrated
source bodies. Its exit codes are `0` for clean, `1` for changes required, and
`2` for blocked. `--write` parses and preflights the complete source tree
before its first atomic file replacement, then preserves an existing UTF-8
byte-order mark. Ambiguous ownership, unsupported legacy arguments, parse
errors, source symlinks, and concurrent source changes fail closed with exit
code `2`. Preflight failures write nothing. A detected write-time change rolls
back only files that still exactly match the tool's output, so the detected
external edit is not overwritten. When ownership is ambiguous, first confirm
the attribute's actual owning module. For InnoDI-owned declarations,
module-qualify the complete macro pair: `@InnoDI.DIContainer` with `@InnoDI.Provide`, or
`@InnoDI.SubContainer` with `@InnoDISwiftUI.DIFeatureRoot`, before rerunning.
The scanner skips `.build`, `.git`, `.swiftpm`, and nested Git repositories;
pass a nested repository as its own `--root` when it must be migrated too.

The public underscored `DIEnvironmentBridging` witness is a breaking rename in
5.0: `_innodiEnvironmentBridgeModifier()` becomes
`_innoDIEnvironmentBridgeModifier()`. Rename any manual conformance or direct
call that used the old spelling. Prefer `@DIEnvironmentBridge` and the public
`.innodi(_:)` view API so application code does not depend on this compiler
support requirement.

Generated conformances now spell the protocol as
`InnoDISwiftUI.DIEnvironmentBridging`, so bridge targets and visible type
binders named `InnoDISwiftUI` must also be renamed.

Generated-name migration for a standalone `@DIEnvironmentBridge` target is
namespace-aware. Rename a direct nested nominal type, protocol, typealias,
static/class variable or function, or enum case named
`_InnoDIEnvironmentBridgeModifier`, and rename a direct instance variable or
zero-parameter instance function named
`_innoDIEnvironmentBridgeModifier`. Top-level `#if` branches follow the same
rules. Uppercase instance values/functions, lowercase static/class members and
parameterized overloads, target and generic parameter names, cross-namespace
declarations, and declarations inside nested bodies do not collide with bridge
synthesis. Use a direct `\EnvironmentValues.member` or
`\SwiftUI.EnvironmentValues.member` mapping; aliases, other roots, chains, and
subscripts are no longer accepted. Change any private target or enclosing
lookup component nested in another nominal to `fileprivate` or default access.
A file-scope private bridge target remains supported. A target that also declares
`@DIContainer` remains subject to the container's broader `_innoDI` and
`_InnoDI` prefix reservation. Move a bridge off any target that declares a
generic parameter pack; use ordinary generic parameters or a non-generic
adapter type.

5.0 splits the component mounting marker by isolation. Ordinary components
continue to conform to `InnoDI._InnoDIComponentMountable`; components whose
container uses `mainActor: true` instead conform to
`InnoDI._InnoDIMainActorComponentMountable`. Hierarchy roots similarly conform
to `InnoDI.DIHierarchyRootMarker`. These module-qualified conformances cannot
be captured by same-named declarations in a consumer module. Update generic
mounting helpers with a separate `@MainActor` actor-marker overload and type its override parameter as
`@MainActor (inout Component._InnoDIComponentOverrides) -> Void`. A helper that
only constrains `_InnoDIComponentMountable` no longer accepts a main-actor
component. Keep a non-`Sendable` mounted result inside the `@MainActor` caller
or the `MainActor.run` block instead of returning it to an off-actor context.
Rename a backtick-escaped `@DIComponent` target to an unescaped Swift
identifier so its generated `<Container>Dependencies` protocol has one
canonical name.

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
An explicitly `private` container must become `fileprivate` for same-file
mounting, or move behind a private namespace while retaining default access.
This prevents generated child-mount APIs from becoming inaccessible to sibling
containers.

Move every provider to a plain stored instance variable:

```swift
// Before: observed/static/accessor-backed provider declarations are unsupported.
@Provide(.shared, factory: Service(), concrete: true)
static var service: Service {
    didSet { audit(service) }
}

// After
@Provide(.shared, factory: Service())
var service: Service
```

Do not attach `_InnoDIProvideAccessor` yourself. It is internal accessor
support synthesized by the container macro for valid provider members.
Keep only one `@Provide` attribute per property, and give every direct provider
property and root factory dependency parameter a unique, unescaped effective
name. Direct `@Provide` and `@SubContainer` properties share one managed-member
identity namespace, so their names must also be unique across roles. Even when
the source names differ, rename a declaration if
`container.generated-symbol-collision` reports that both declarations map to
the same hidden peer. `@SubContainer` property names must also be unescaped and declared
exactly once as direct plain stored instance variables outside `#if`. Do not
attach `_InnoDISubContainerAccessor`; the parent container owns it. A deliberately forged
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
    })
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

The stable diagnostics, `InnoDI-Migrate` command, and before/after examples in
this section are part of the 5.0 release candidate. Run the migration command
with `--check` after reviewing any write-mode changes so unresolved or
unsupported sites fail closed before adopting 5.0.

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
- In 4.x, container members whose names began with `_storage_`,
  `_override_sub_`, `_innoDISubBuild_`, `_innoDIUnresolvedDependency`,
  `_subBuildCell_`, `_lazyCell_`, or `_lazySelfForSub` were rejected with
  `container.reserved-name-prefix`. In 5.0 the canonical generated prefixes
  are `_storage_`, `_override_`, `_innoDI`, and `_InnoDI`, so the first four
  examples remain reserved by those broader prefixes. Former local spellings
  outside that namespace — `_subBuildCell_`, `_lazyCell_`, `_lazySelfForSub`,
  `_resolved_`, and `_task_` — are available again.

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
