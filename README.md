# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

Macro-driven dependency injection for Swift with compile-time and build-time
validation, dependency-graph tooling, hierarchy checks, and SwiftUI helpers.

## Minimum Useful Example

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## Why InnoDI

InnoDI is designed for teams that want DI wiring to stay explicit and
reviewable while moving failure detection earlier.

- `@DIContainer` and `@Provide` generate container APIs from supported,
  effectively non-generic Swift structs.
- Macro validation catches local mistakes at expansion time.
- Build validation and the graph CLI catch cross-file, cross-module, and global graph issues.
- `InnoDISwiftUI` removes repetitive root-boundary environment wiring.

InnoDI is not a runtime state machine. Runtime state belongs in your app layer
or companion frameworks such as `InnoFlow`, `InnoRouter`, and `InnoNetwork`.
It intentionally does not provide an `@Injected` property wrapper or dynamic
registration API; the tradeoff is explicit generated initializers, reviewable
wiring, and earlier validation.

## When to Choose InnoDI

Choose InnoDI when dependency wiring should be visible in code review, validated
before runtime, and inspectable as a graph artifact.

| If your priority is... | Prefer... | Why |
| --- | --- | --- |
| Compile/build-time validation of an app dependency graph | InnoDI, [SafeDI](https://github.com/dfed/SafeDI), or [Needle](https://github.com/uber/needle) | InnoDI keeps the container surface in macro-expanded Swift, adds local macro diagnostics, build-support checks, and a DAG CLI. SafeDI and Needle are also compile-time-oriented, but bring their own generator/component workflows. |
| Runtime registration, late binding, or plugin-like composition | [Swinject](https://github.com/Swinject/Swinject) or [Factory](https://github.com/hmlongco/Factory) | Runtime containers make it easy to swap registrations dynamically. InnoDI intentionally favors explicit generated initializers and early validation over dynamic lookup. |
| SwiftUI previews and scoped test overrides with minimal graph ceremony | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), or InnoDI | Factory and swift-dependencies are very ergonomic for scoped overrides. InnoDI is a better fit when those overrides should sit on top of a validated app container and generated SwiftUI root helpers. |
| Hierarchical feature ownership and graph visibility | InnoDI, [Needle](https://github.com/uber/needle), or [SafeDI](https://github.com/dfed/SafeDI) | InnoDI models parent-owned child containers with `@SubContainer` and renders ownership edges in the graph CLI. Needle and SafeDI are strong options when their component/dependency-tree architecture matches your app. |
| Lowest adoption cost for an existing app | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), or incremental InnoDI adoption | InnoDI asks you to define containers and accept macro/build validation. That cost pays off most when you want reviewable wiring, generated overrides, and graph checks rather than only localized dependency access. |

In practice, InnoDI can also coexist with runtime tools: use InnoDI for the
validated application graph, then use `swift-dependencies` or small factories
inside feature logic when scoped runtime values are the better abstraction.

The layering pattern that works well is to keep InnoDI in charge of construction and
let `swift-dependencies` carry the ephemeral, per-call overrides. The composition
root resolves a `DependencyKey` (for example `@Dependency(\.date)`) and passes the
value into the container as an `.input` slot; tests use
`withDependencies { $0.date = .constant(...) } operation:` to swap that value for a
single call tree without rebuilding the container or its validated graph. InnoDI's
container-level `Overrides` builder remains the right tool for app-wide swaps such
as a fake `APIClient`; reach for `swift-dependencies` only when an override should
live for the duration of one operation.

## Requirements

- Swift tools version `6.2` (CI validates Swift 6.2 and 6.3)
- Platforms:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### Filesystem requirements for the build-time validator

The build plugin serializes live DAG validation runs through a layered
POSIX lock under SwiftPM's plugin work directory, which follows the Swift
Package Manager scratch directory:

1. `open(O_CREAT | O_EXCL | O_RDWR)` creates a single lock file.
2. `flock(LOCK_EX | LOCK_NB)` adds an advisory exclusive lock on the
   descriptor.

InnoDI auto-detects the filesystem backing that lock directory. Local
filesystems such as APFS, HFS+, ext4, btrfs, xfs, and tmpfs are supported.
NFS mounts, SMB/CIFS, WebDAV, and FUSE-style filesystems are refused by default
because concurrent builds can corrupt the shared validation cache when lock
atomicity is not reliable.

If your build system must place derived data on a shared volume, point SPM's
`--scratch-path` (or Xcode's derived-data location) at a local directory:

```sh
swift build --scratch-path /tmp/innodi-cache
```

The plugin does not create lock/cache state under the package root
`.build/innodi-dag-validation`; moving the scratch path moves the validation
state as well.

Operators can bypass the unsafe-filesystem fail-fast with
`INNODI_ALLOW_UNSAFE_LOCK=1`, but InnoDI still emits an auditable warning and
the risk stays with that build environment. For diagnostics, recovery steps,
and the full filesystem table, see
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md).

The build-time validator exposes two opt-out escape hatches for fast iteration
or constrained environments: `@DIContainer(validateDAG: false)` per container,
and `INNODI_DISABLE_BUILD_VALIDATION=1` to short-circuit the entire build
plugin. Every PR runs `Tools/report-validate-dag-escape-hatches.sh`, which
lists every site that uses these escape hatches in the workflow's step summary
so escape-hatch creep stays visible without a separate CI gate. Production CI
must leave both unset.

## Privacy

InnoDI ships an Apple Privacy Manifest (`PrivacyInfo.xcprivacy`) with both
runtime products, `InnoDI` and `InnoDISwiftUI`. The manifest declares no user
tracking, no tracking domains, no collected data types, and no Required Reason
API usage. Build-time tools — `InnoDIBuildSupport`, the dependency-graph CLI,
and the macro plugin — are not embedded in consumer apps and therefore do not
contribute to the manifest. If you embed InnoDI into an iOS, watchOS, tvOS, or
visionOS app, the manifest is bundled automatically by SwiftPM and surfaces in
your aggregated privacy report.

## Installation

Add InnoDI to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "5.0.0")
]
```

Then add the products you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

Add `InnoDISwiftUI` only if you also need the SwiftUI helpers:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Attach the build-time validation plugin to every target that declares InnoDI
containers or a standalone `@DIEnvironmentBridge`. This is a required part of
the 5.0 correctness contract, not only an optional graph visualization step.
The target-scoped full-source pass rejects custom initializers in sibling
extensions, generated-qualifier shadows in enclosing or other same-target
declarations, visible qualifier shadows with `public` or `package` access in
imported dependency targets, and direct-extension or standalone-local bridge
targets that attached macros cannot validate alone.

When a generated site is a class or is nested inside a class, the first
inherited type (the position that can name its superclass) must resolve through
source-visible declarations and typealiases. An SDK-only, binary-only,
unresolved, or ambiguous first inherited type fails closed with
`generated-qualifier.inheritance-unverifiable`; move the generated site to a
struct/enum or a source-visible adapter, or make the superclass chain available
to the target-scoped source snapshot. This preflight is a conservative
syntactic index, not a replacement for Swift's type checker.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

As of 5.1, the same product also conforms to the native Xcode build-tool plugin
API. Native Xcode projects and Tuist-generated projects can attach the package
plugin directly to each container target. For a Tuist workspace, the plugin
discovers the workspace root and validates all production Swift sources so
cross-project container references are included in the source DAG.

The Xcode plugin API does not expose Tuist's complete cross-project target
dependency topology. The 5.1 fallback therefore preserves full-source DAG and
declaration validation but cannot prove every module-edge hierarchy rule from
Xcode alone; keep a topology-aware SwiftPM or CI hierarchy check when
`@DIComponent` / `@DIHierarchyRoot` module relationships are a release gate.
Xcode validation intentionally declares no output files because
multi-destination variants share a plugin work directory, so Xcode may report
that the validation command runs during every build.

## Quick Start

<!-- innodi:compile -->
```swift
import Foundation
import InnoDI

protocol APIClientProtocol {
    func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    func fetch() async throws -> Data { Data() }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
```

Use a factory closure when names or construction logic do not line up with
`Type.self` plus `with:`:

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## Read This Next

Start with these documents in order:

1. [Overview](Sources/InnoDI/InnoDI.docc/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

## Core API

### `@DIContainer`

`@DIContainer` synthesizes:

1. A primary `init(...)` with required `.input` parameters and optional
   overrides for `.shared`, `.transient`, and `@SubContainer` members.
2. A nested `Overrides` type.
3. A convenience `init(<inputs...>, _ applyOverrides: (inout Overrides) -> Void)`.
4. Four `withOverrides` overloads for `sync`, `throws`, `async`, and
   `async throws` operations.

Every container, including one with no managed members, synthesizes the full
overrides scaffolding. A user-declared nested `Overrides` type is unsupported
in InnoDI 5.0 and emits `container.overrides-name-conflict`; rename it so the
macro can own the mountable override ABI.

The macro also emits the reserved compiler-support alias
`_InnoDIMountOverrides = Overrides` for generated parent mounting code. Do not
declare or reference that underscored name directly.

Every stored instance member in a container must use `@Provide` or
`@SubContainer`; computed and static properties remain available. This keeps
the generated initializer complete and prevents memberwise-initializer drift.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Meaning |
|---|---|---|
| `root` | `false` | Graph-render entry flag only. If any roots exist, Mermaid, DOT, and ASCII output is pruned to the union of root-reachable nodes and edges. |
| `validateDAG` | `true` | Enables global DAG validation plus the macro's local graph-derived checks. `false` skips global DAG and local cycle checks, but declaration validation and effect compatibility on explicit sibling edges still run. |
| `mainActor` | `false` | Applies `@MainActor` to dependency accessors, all generated initializers, `Overrides`, the `applyOverrides` function types used by convenience initializers, `withOverrides`, child overrides, and component mounting, all four `withOverrides` operation closures, and feature-root helpers. With `@DIComponent`, it also isolates the generated dependency protocol and `init(dependencies:_:)`, and uses the dedicated `_InnoDIMainActorComponentMountable` conformance. Components without the option continue to use `_InnoDIComponentMountable`. Recommended for UI-root containers. |

In 5.0, generic component-mounting helpers must distinguish the two marker
protocols. Keep `_InnoDIComponentMountable` for ordinary components and add an
`@MainActor` overload constrained to `_InnoDIMainActorComponentMountable`, with
an `@MainActor` override closure, for `mainActor: true` components.

Keep non-`Sendable` container/component values on the main actor by using an
`@MainActor` caller or constructing and consuming them inside `MainActor.run`.
A direct `await` is appropriate for an isolated operation that returns a
`Sendable` result, such as a `withOverrides` operation result; it does not make
the container itself safe to carry off actor.

`@DIContainer` does not support user-defined `init` declarations in the
annotated type or matching extensions. Use the synthesized initializer or wire
the type manually without the macro. The macro diagnoses initializers in the
annotated body; the required build plugin diagnoses same-file and cross-file
extension initializers before compilation.

InnoDI 5.0 supports `@DIContainer` only on an effectively non-generic `struct`
declared at file scope or as a member of non-generic nominal declarations.
Neither the struct nor an enclosing nominal declaration may introduce generic
parameters or a generic `where` clause. Classes, actors, enums, protocols,
extension declarations, structs declared inside extensions, and structs in
executable scopes such as functions, closures, accessors, or switch cases are
rejected. The same boundary applies when `@DIComponent` is stacked on the
container. Move runtime or type-specific state behind injected protocol
dependencies or `@Provide(.input)` values.

An explicitly `private` container is also rejected because sibling containers
cannot access its generated mount surface. Use `fileprivate` for file-local
mounting, or put a default-access container inside a private namespace.

The Swift compiler currently omits accessor ancestry when expanding an
attached macro on a type declared inside a computed-property body. The InnoDI
build-validation plugin and dependency-graph CLI scan the full source tree and
enforce the same local-scope rejection for that compiler edge case. They also
see sibling extensions that compiler-plugin macro input omits. Attach the plugin
to every target that declares containers when adopting the 5.0 declaration
contract. Without that full-source preflight, extension custom initializers can
bypass the policy, and a local container stacked with companion macros such as
`@DIComponent` can surface compiler or companion-macro errors in addition to,
or instead of, the stable InnoDI diagnostic.

### `@Provide` and scopes

InnoDI 5.0 supports `@Provide` only on a direct, plain, stored instance `var` in
the same supported `struct` that carries `@DIContainer`. `let`, computed or
observed properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone,
and indirectly nested uses are rejected. InnoDI owns the generated provider
accessor; never attach `_InnoDIProvideAccessor` manually.

Provider declarations use a closed attribute and access-control surface.
Property wrappers, conditional or unknown attributes, setter access modifiers
such as `private(set)`, and global-actor attributes are rejected. Besides
`@Provide` itself, no source-written property-level attribute is supported.
This prohibition includes `@MainActor`; request actor isolation with
`@DIContainer(mainActor: true)`. The isolation attributes InnoDI generates on
the provider declaration and accessor remain internal compiler support. A
complete `@Provide` member declaration inside `#if` is also rejected with
`provide.conditional-declaration-unsupported`; keep the declaration
unconditional and branch inside its factory or injected implementation.
Attach exactly one `@Provide` per property. Duplicate attributes are rejected
with `provide.duplicate-attribute`. Direct provider properties and root factory
closure dependency parameters must each have unique effective names; duplicate
identities are rejected before generated lookup or storage code is emitted.
Both declaration kinds must use unescaped identifiers; backtick-escaped
property and factory-parameter names are rejected in 5.0. `@SubContainer`
property names must also be unescaped because generated child storage,
overrides, and root-helper identities derive from them.
Generated storage/support declarations reserve `_storage_`, `_override_`,
`_innoDI`, and `_InnoDI`; the exact direct declaration name `InnoDI` is also
reserved, while `Swift`, `_Concurrency`, and SwiftUI bridge anchors are
reserved in the type namespace visible to the attached macro. See the 5.0 section of the
[Migration Guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md) for the exact
matrix. The target-scoped full-source pass rejects same-named declarations in
enclosing scopes or elsewhere in the target, plus visible declarations with
`public` or `package` access in imported dependency targets, when they shadow a
generated qualifier that SwiftSyntax hides from the attached macro.
For a class bridge or an enclosing class, that scan follows a source-visible
superclass chain: inherited type members named `Swift` or `SwiftUI` are
rejected, while an inherited `InnoDISwiftUI` member is safe. A directly or
lexically visible `InnoDISwiftUI` declaration remains reserved. Because this is
a conservative syntactic index, an SDK-only, binary-only, unresolved, or
ambiguous first inherited type fails closed with
`generated-qualifier.inheritance-unverifiable` rather than assuming the
superclass is shadow-free.
The explicit property type must not be an
opaque `some Protocol` or an implicitly unwrapped optional `T!`; expose an
existential `any Protocol`, or use explicit `T` / `T?`, respectively. A
deliberately forged combination of the compiler-support accessor with another
property wrapper can also receive Swift's own structural diagnostics in
addition to InnoDI's misuse diagnostic.

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    escaping: Bool = false
)
```

| Scope | Meaning | Construction rules |
|---|---|---|
| `.input` | External dependency supplied at container initialization | Declares no `factory:`, `asyncFactory:`, `Type.self`, property initializer, or `with:` |
| `.shared` | Created once per container instance and reused | Declares exactly one of `factory:`, `asyncFactory:`, `Type.self`, or a property initializer |
| `.transient` | Recreated on every access | Declares exactly one of `factory:`, `asyncFactory:`, `Type.self`, or a property initializer |

Additional rules:

- The four construction sources—`factory:`, `asyncFactory:`, `Type.self`, and
  a property initializer—are mutually exclusive for `.shared` and `.transient`.
- `.input` rejects every construction source and rejects `with:`.
- Generated `.input` initializer parameters are eager values of the declared
  type `T`; Swift evaluates `try` / `await` argument expressions before the
  initializer call as usual. Directly spelled non-optional function types are
  detected automatically and emitted as escaping parameters. For a
  non-optional function type hidden behind a typealias, write
  `@Provide(.input, escaping: true)`. `escaping:` must be a literal Boolean and
  is valid only for `.input`. Obvious nonfunction and optional-function shapes
  are rejected; if an accepted identifier/member alias does not actually
  resolve to a non-optional function, Swift may emit its own diagnostic.
- `asyncFactory` is supported for `.shared` and `.transient` and must be an
  `async` closure.
- `with:` is valid only with the `Type.self` construction form. It must be a
  literal array whose entries use exactly the canonical direct-member spelling
  `\Self.member`, such as `with: [\Self.config]`; `with: []` is also valid.
  Named container, module-qualified, and typealias roots are rejected, as are
  nested components, optional chaining, subscripts, and computed array
  elements. Every referenced provider must use synchronous construction.
- The declared property type determines the storage shape: a concrete nominal
  type uses concrete storage, while `any Protocol` uses existential storage.
- Name resolution for factory parameters and `with:` wiring is strict by member name.

Sibling DI edges use a closed syntax:

- A root `factory:` or `asyncFactory:` closure literal declares one edge for
  each named parameter. Nested closures and arbitrary identifiers do not add
  edges.
- `Type.self` construction declares edges from its literal canonical
  `\Self.member` key-path array and can target synchronous providers only.
- A non-closure `factory:` expression or property initializer is an opaque,
  zero-edge construction source. It must not reference sibling container
  members. Rewrite sibling wiring as root closure parameters; when no DI edge
  is intended, call a qualified global/static construction symbol instead.

Factory effects are explicit and are not inferred from dependencies. Use
`asyncFactory:` for an asynchronous consumer and spell `async throws` on that
closure when it consumes a throwing asynchronous provider. Effect
compatibility is validated on every explicit edge even with
`validateDAG: false`.

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | allowed | allowed | allowed |
| `async` | rejected | allowed | allowed |
| `async throws` | rejected | rejected | allowed |

`Lazy<T>` and `Provider<T>` are synchronous deferred wrappers. Their targets
must use synchronous construction; an async target is rejected.

## Validation Model

InnoDI validates containers in layers:

1. Macro validation
   - compiler-exposed local scope rules
   - missing factories
   - declaration-order checks
   - local cycles
   - invalid `init` declarations
2. Build validation
   - full-source declaration-matrix preflight
   - cross-file `init` conflicts
   - semantic reference checks
   - hierarchy validation
   - artifact generation
3. Global DAG validation
   - `swift run InnoDI-DependencyGraph --root . --validate-dag`

`validateDAG: false` is intentionally narrow. It opts a container out of global
DAG validation plus local cycle and other graph-derived checks. It does not
disable declaration validation or effect compatibility on explicit
root-closure/`with:` sibling edges.

## Overrides Builder

The generated `Overrides` builder lets tests override only the members they
care about.

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

Or scope the override to one operation:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

Important details:

- Input-only containers still synthesize an empty builder.
- If a child container is input-only, `<name>Overrides` closures still compile
  and execute as no-ops until the child gains overrideable members.
- A container must not declare its own nested `Overrides` type. InnoDI 5.0
  rejects that collision instead of emitting a partial, non-mountable API.

## `Lazy<T>` and `Provider<T>`

Use `Lazy<T>` when a factory needs a deferred reference that should be excluded
from cycle detection.

Use `Provider<T>` when a factory needs to re-enter a `.transient` dependency on
every call.

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
})
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
})
var logger: RequestLogger
```

Both wrappers are intentionally non-`Sendable` and must stay on the container's
original isolation domain. They also remain synchronous: neither wrapper can
target an `asyncFactory` member.

## Nested Containers and Hierarchy

`@SubContainer` models parent-owned child containers:

```swift
@SubContainer(
    scope: .shared,
    with: [\.config, \.apiClient],
    featureRoot: FeatureRootScene.self
)
var feature: FeatureContainer
```

Key rules:

- `scope:` is required.
- Declare exactly one `@SubContainer` on a direct, plain, stored instance `var`
  in its supported parent `@DIContainer`, outside `#if`. Wrappers, storage or
  accessor modifiers, unknown attributes, and manual attachment of
  `InnoDI._InnoDISubContainerAccessor` are unsupported.
- Implicit same-name wiring is only a convenience for zero or one parent
  `@Provide` candidate. If the parent has multiple candidates, add explicit
  wiring instead of relying on generated Swift initializer errors.
- `with:` forwards an explicit same-name subset or order. It must be a
  literal key-path array the macro can read; runtime variables or
  computed array elements are unsupported.
- `with: []` is an explicit empty subset and calls `Child()`.
- `bindings:` remaps child input labels to different parent member names.
- `featureRoot:` / `featureRoots:` generate SwiftUI root helpers on the parent
  container without stacking another peer macro on the same property.
- Choose exactly one wiring form: `with:` or `bindings:`.
- Parent `Overrides` gain both a full replacement slot (`feature`) and a child
  override closure (`featureOverrides`).

Cross-module ownership uses:

- `@DIComponent` for mountable child containers
- `@DIHierarchyRoot` for rooted workspace-level validation

## SwiftUI Helpers

`InnoDISwiftUI` adds a small SwiftUI integration layer on top of the container
contract:

- `.innodi(container)` applies a generated environment bridge to a view tree.
- `@DIEnvironmentBridge` maps container members into SwiftUI environment keys.
- `@SubContainer(..., featureRoot:)` and `featureRoots:` generate default or
  named feature-root helpers for child containers.
- InnoDI 5.0 removes the deprecated `@DIFeatureRoot` compatibility macro.
  Replace it with the `@SubContainer` arguments so helper generation stays in
  the container macro pipeline and does not stack peer macros on one property.

Use `@DIContainer(mainActor: true)` for UI-root containers when you want the
generated container API isolated to the main actor. A paired `@DIComponent`
also isolates its `<Container>Dependencies` protocol, `init(dependencies:_:)`,
and override-application closure types, and conforms to the dedicated
`_InnoDIMainActorComponentMountable` protocol. Ordinary components continue to
use `_InnoDIComponentMountable`. Keep non-`Sendable` construction and use on
the main actor; use direct `await` only when the isolated operation returns a
`Sendable` result.

## CLI and Release Surface

Render a graph:

```bash
swift run InnoDI-DependencyGraph --root . --root-pruning all
```

Validate the global DAG:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

Inspect the Swift generated by macros for a consumer target:

```bash
Tools/dump-macro-expansions.sh \
  --package-path /path/to/ConsumerPackage \
  --target App
```

Run the script from an InnoDI checkout and point `--package-path` at the
consumer. It performs an isolated scratch build, writes the combined result to
the consumer's `.build/innodi/macro-expansions.swift` by default, and refuses
to place generated fragments under `Sources/` or `Tests/`. The consumer's
normal build cache is left untouched. In Xcode, **Expand Macro** remains the
fastest way to inspect one declaration; this command is for a complete,
reviewable target artifact.

Generate DocC:

```bash
Tools/generate-docc.sh
```

Release notes and upgrade notes live in [RELEASING.md](RELEASING.md).

## Examples

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
