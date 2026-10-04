# InnoDI

[![Release](https://img.shields.io/github/v/release/InnoSquadCorp/InnoDI)](https://github.com/InnoSquadCorp/InnoDI/releases) [![License](https://img.shields.io/github/license/InnoSquadCorp/InnoDI)](LICENSE) [Swift Package Index](https://swiftpackageindex.com/InnoSquadCorp/InnoDI) · [CI and public operations](docs/automation-policy.md)

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

> [!IMPORTANT]
> This checkout documents **unreleased 7.0.0**. Its examples and rules require the 7.0 development checkout, not the published 6.0.0 package.
> [Stable 6.0.0 documentation](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.md).

Macro-driven dependency injection for Swift with compile-time and build-time
validation, dependency-graph tooling, hierarchy checks, and SwiftUI helpers.

## Minimum Useful Example

First complete [Installation](#installation), including the required validation
plugin. This example constructs the same service with live and test values.

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Input var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let live = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = APIClient(baseURL: "https://test.example.com")
}
precondition(live.apiClient.baseURL == "https://api.example.com")
precondition(test.apiClient.baseURL == "https://test.example.com")
```

For expensive shared services that may never be used, opt into first-access
construction. Container copies retain one logical cache, while separately
initialized containers remain isolated:

```swift
@Provide(.shared, initialization: .onDemand, factory: MetricsClient())
var metrics: MetricsClient
```

The generated `prewarm` method resolves only selected on-demand providers;
`Lazy` and `Provider` dependencies remain deferred. The same
`initialization: .onDemand` option works with `asyncFactory:`, and the
container then gains `closeAsyncProviders()`. For asynchronous work that needs
readiness, retry, and explicit shutdown, start with
[`generateOwned: true` and owned containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md).
`makeOwned` does not mean ready. When using the report-returning `prepare`,
check `report.isReady` before proceeding.

## Why InnoDI

InnoDI is designed for teams that want DI wiring to stay explicit and
reviewable while moving failure detection earlier.

- `@DIContainer` and `@Provide` generate container APIs from supported,
  effectively non-generic Swift structs.
- Macro validation catches local mistakes at expansion time.
- Build validation and the graph CLI catch cross-file, cross-module, and global graph issues.
- `InnoDISwiftUI` removes repetitive root-boundary environment wiring.
- `InnoDITesting` provides opt-in concurrency-safe mock storage, generation-
  aware reset, interaction validation, and typed override presets for test and
  preview targets.

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

Moving an existing app? Follow
[Migrating from Factory](Sources/InnoDI/InnoDI.docc/MigratingFromFactory.md) or
[Migrating from Swinject](Sources/InnoDI/InnoDI.docc/MigratingFromSwinject.md)
for a concept map, migration steps, and a compiled example.

In practice, InnoDI can also coexist with runtime tools: use InnoDI for the
validated application graph, then use `swift-dependencies` or small factories
inside feature logic when scoped runtime values are the better abstraction.

The layering pattern that works well is to keep InnoDI in charge of construction and
let `swift-dependencies` carry the ephemeral, per-call overrides. The composition
root resolves a `DependencyKey` (for example `@Dependency(\.date)`) and passes the
value into the container as an `@Input` slot; tests use
`withDependencies { $0.date = .constant(...) } operation:` to swap that value for a
single call tree without rebuilding the container or its validated graph. InnoDI's
container-level `Overrides` builder remains the right tool for app-wide swaps such
as a fake `APIClient`; reach for `swift-dependencies` only when an override should
live for the duration of one operation.

## Requirements

- Swift tools version `6.2` (CI validates Swift 6.2 / 6.3 / 6.4; macro builds use the SwiftSyntax prebuilt on Xcode 27 / Swift 6.4)
- Platforms:
  - iOS 17+
  - macOS 14+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

InnoDI supports Apple platforms only. CI does not build or test Linux, and
`InnoDITesting` imports Apple's `os` module unconditionally.

The build-time validator keeps its lock and cache under SwiftPM's scratch
directory, which must be on a local filesystem such as APFS. It refuses NFS,
SMB, WebDAV, and FUSE mounts by default; see
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md) for the filesystem
table and recovery steps.

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

Installation takes three steps: add the package, attach the validation
plugin, and write a first container.

### 1. Add the package

Add InnoDI to your `Package.swift`:

```swift
dependencies: [
    .package(name: "InnoDI", path: "../InnoDI")
]
```

For the examples on this page, use the local **7.0 development checkout** above (adjust `../InnoDI` to its path). No 7.0.0 release tag is available yet.

For the published **6.0.0** package, use the dependency below and follow the linked stable documentation, not this page's 7.0 examples.
[Stable 6.0.0 documentation](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.md).

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "6.0.0")
]
```

The remaining product, plugin, and API examples on this page use the **7.0 development checkout**.
For the source changes from 6.x, follow the
[migration guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#6x--70).

Then add the products you need. `InnoDI` is the core. Add `InnoDISwiftUI` for
the SwiftUI helpers, and add `InnoDITesting` only to test or preview-support
targets that use generated mocks or override presets; see
[Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md).

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

### 2. Attach the validation plugin

Attach `InnoDIDAGValidationPlugin` to every target that declares an InnoDI
container or a standalone `@DIEnvironmentBridge`. The plugin is part of the
correctness contract: before Swift compiles the target, it checks what an
attached macro cannot see, such as custom initializers in other files,
qualifier shadows, and the global dependency graph.

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

The same plugin works in native Xcode and Tuist projects. The
[Integration Guide](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md#build-plugin)
covers the Xcode and Tuist limits, the superclass rule behind
`generated-qualifier.inheritance-unverifiable`, and the scratch-path
requirement. [Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)
describes the per-container `validateDAG: false` and build-wide
`INNODI_DISABLE_BUILD_VALIDATION=1` escape hatches, which production CI must
leave unset.

### 3. Write your first container

Continue with the Quick Start below. The
[tutorial](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md) builds a container
step by step.

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
    @Input
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient

struct MockAPIClient: APIClientProtocol {
    func fetch() async throws -> Data { Data([0x01]) }
}
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = MockAPIClient()
}
_ = test.apiClient
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

Start with the task you need:

1. Synchronous services and values: [Overview](Sources/InnoDI/InnoDI.docc/Overview.md)
2. Asynchronous readiness and shutdown: [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md)
3. Tests and previews: the mock override in Quick Start above, then [Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md)

For failures, see [Validation](Sources/InnoDI/InnoDI.docc/Validation.md) and
[Policy Boundaries](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md). For upgrades,
see [CHANGELOG.md](CHANGELOG.md).

## Core API

### `@DIContainer`

`@DIContainer` synthesizes:

1. A primary `init(...)` with required `@Input` parameters and optional
   overrides for `.shared`, `.transient`, and `@SubContainer` members.
2. A nested `Overrides` type.
3. A convenience `init(<inputs...>, _ applyOverrides: (inout Overrides) -> Void)`.
4. Four `withOverrides` overloads for `sync`, `throws`, `async`, and
   `async throws` operations.

Every container, including one with no managed members, synthesizes the full
overrides scaffolding. A user-declared nested `Overrides` type is unsupported
in InnoDI 6.0 and emits `container.overrides-name-conflict`; rename it so the
macro can own the mountable override ABI.

The macro also emits the reserved compiler-support alias
`_InnoDIMountOverrides = Overrides` for generated parent mounting code. Do not
declare or reference that underscored name directly.

Every stored instance member in a container must use `@Provide` or
`@SubContainer`; computed and static properties remain available. This keeps
the generated initializer complete and prevents memberwise-initializer drift.

```swift
@DIContainer(
    validateDAG: Bool = true,
    initializationOrder: String = ContainerInitializationOrder.declaration,
    generateOwned: Bool = false
)
@DIContainerRole(
    role: String,
    mainActor: Bool = false,
    validateDAG: Bool = true,
    initializationOrder: String = ContainerInitializationOrder.declaration,
    generateOwned: Bool = false
)
```

| Parameter | Default | Meaning |
|---|---|---|
| `role` | required for `@DIContainerRole` | `ContainerRole.local`, `.component`, or `.root`. Root role selects graph-render reachability; component role exposes the cross-module mount contract. |
| `validateDAG` | `true` | Enables global DAG validation plus local graph-derived checks. `false` skips global DAG and local availability checks; local ownership-cycle, declaration, and explicit sibling effect checks remain mandatory. |
| `mainActor` | `false` | Applies `@MainActor` to dependency accessors, all generated initializers, `Overrides`, the `applyOverrides` function types used by convenience initializers, `withOverrides`, child overrides, and component mounting, all four `withOverrides` operation closures, and feature-root helpers. With `@DIContainerRole(role: ContainerRole.component)`, it also isolates the generated dependency protocol and `init(dependencies:_:)`, and uses the dedicated `_InnoDIMainActorComponentMountable` conformance. Components without the option continue to use `_InnoDIComponentMountable`. Recommended for UI-root containers. |
| `initializationOrder` | `ContainerInitializationOrder.declaration` | Opt into `.dependency` with the full named token to construct shared providers in dependency order. Review factory side effects before adopting. |
| `generateOwned` | `false` | Generates `makeOwned(...)` and a separate owned view for readiness, retry, and shutdown. Custom methods and conformances on the original container do not transfer to the view. |

## Opt-in Dependency Ordering

The default `ContainerInitializationOrder.declaration` preserves the existing
construction rules. Select `ContainerInitializationOrder.dependency` to wire
acyclic shared providers without moving their declarations above their users.
Only these named tokens, optionally qualified with `InnoDI.`, are accepted;
string literals, variables, and shorthand `.dependency` are not supported.

```swift
@DIContainer(initializationOrder: ContainerInitializationOrder.dependency)
struct AppContainer {
    @Provide(.shared, factory: { (configuration: Configuration) in
        Client(configuration: configuration)
    }) var client: Client
    @Provide(.shared, factory: Configuration()) var configuration: Configuration
}
```

The macro orders synchronous shared construction first, then asynchronous
shared handle creation. Within each stage, a hard dependency precedes its
consumer; among ready providers the earliest source declaration wins. Already
valid declaration-ordered containers retain their construction order. Inputs,
initializer argument order, override fields and child mounting stay unchanged.

This is an explicit behavior choice: a forward dependency can move observable
factory side effects. Review initialization traces when adopting it; no factory
is assumed pure. Async completion order is still determined by execution, and
independent tasks are not serialized. On-demand providers remain on-demand;
ordering their capture/cell setup does not prewarm unused services.

`Lazy` and `Provider` edges remain deferred, but still count for ownership-cycle
validation. Cycles remain errors, including with `validateDAG: false`. The opt-in
does not permit a sync factory to consume async work, a shared hard edge to a
transient provider, or a provider to depend on a child container. It does not
change close, cancellation, retry, or container-copy lifetime contracts.

Existing containers need no migration. Adoption adds one argument; do not
mechanically reorder declarations or change the default across an app without
reviewing side effects. This API is included in the unreleased 7.0 candidate;
public API baseline review and supported Apple toolchain qualification remain
pending.


In 6.0, generic component-mounting helpers must distinguish the two marker
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

InnoDI 6.0 supports `@DIContainer` only on an effectively non-generic `struct`
declared at file scope or as a member of non-generic nominal declarations.
Neither the struct nor an enclosing nominal declaration may introduce generic
parameters or a generic `where` clause. Classes, actors, enums, protocols,
extension declarations, structs declared inside extensions, and structs in
executable scopes such as functions, closures, accessors, or switch cases are
rejected. The same boundary applies to `@DIContainerRole`. Move runtime or
type-specific state behind injected protocol dependencies or `@Input` values.

An explicitly `private` container is also rejected because sibling containers
cannot access its generated mount surface. Use `fileprivate` for file-local
mounting, or put a default-access container inside a private namespace.

The Swift compiler currently omits accessor ancestry when expanding an
attached macro on a type declared inside a computed-property body. The InnoDI
build-validation plugin and dependency-graph CLI scan the full source tree and
enforce the same local-scope rejection for that compiler edge case. They also
see sibling extensions that compiler-plugin macro input omits. Attach the plugin
to every target that declares containers when adopting the 6.0 declaration
contract. Without that full-source preflight, extension custom initializers can
bypass the policy, and an invalid local role container can surface compiler or
macro errors in addition to, or instead of, the stable InnoDI diagnostic.

### `@Provide` and scopes

InnoDI 6.0 supports `@Provide` only on a direct, plain, stored instance `var` in
the same supported `struct` that carries `@DIContainer`. `let`, computed or
observed properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone,
and indirectly nested uses are rejected. InnoDI owns the generated provider
accessor; never attach `_InnoDIProvideAccessor` manually.

Provider declarations use a closed attribute and access-control surface.
Property wrappers, conditional or unknown attributes, setter access modifiers
such as `private(set)`, and global-actor attributes are rejected. Besides
`@Provide` itself, no source-written property-level attribute is supported.
This prohibition includes `@MainActor`; request actor isolation with
`@DIContainerRole(role: ContainerRole.local, mainActor: true)`. The isolation attributes InnoDI generates on
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

For a machine-readable migration inventory before any write, run
`swift run InnoDI-Migrate --root . --report --output migration-report.json`.
The schema-v1 report contains paths and diagnostics, never source bodies, and
uses exit codes `0` (clean), `1` (changes required), and `2` (blocked).

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

| Scope | Meaning | Construction rules |
|---|---|---|
| `@Input` | External dependency supplied at container initialization | Declares no `factory:`, `asyncFactory:`, `Type.self`, property initializer, or `with:` |
| `.shared` | Created once per container instance and reused | Declares exactly one of `factory:`, `asyncFactory:`, `Type.self`, or a property initializer |
| `.transient` | Recreated on every access | Declares exactly one of `factory:`, `asyncFactory:`, `Type.self`, or a property initializer |

Additional rules:

- The four construction sources—`factory:`, `asyncFactory:`, `Type.self`, and
  a property initializer—are mutually exclusive for `.shared` and `.transient`.
- `@Input` rejects every construction source and rejects `with:`.
- Generated `@Input` initializer parameters are eager values of the declared
  type `T`; Swift evaluates `try` / `await` argument expressions before the
  initializer call as usual. Directly spelled non-optional function types are
  detected automatically and emitted as escaping parameters. For a
  non-optional function type hidden behind a typealias, write
  `@Input(escaping: true)`. `escaping:` must be a literal Boolean and
  is valid only for `@Input`. Obvious nonfunction and optional-function shapes
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
| `async` or `async throws`, `.onDemand` | rejected | rejected | allowed |

`Lazy<T>` and `Provider<T>` are synchronous deferred wrappers. Their targets
must use synchronous construction; an async target is rejected.

A `.shared` provider built by `asyncFactory:` starts its construction task in
the container initializer, before any read, and the container never cancels
that task. Each read of a `.transient` `@SubContainer` therefore starts the
child's eager asynchronous work again. Add `initialization: .onDemand` to
start construction on the first read instead. Its accessor always throws, and
the generated `closeAsyncProviders()` cancels in-flight work and closes the
provider. See
[Asynchronous Shared Lifetime](Sources/InnoDI/InnoDI.docc/Provide.md#asynchronous-shared-lifetime)
for the cancellation contract and alternatives.

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
DAG validation plus local graph-derived availability checks. It does not disable local ownership-cycle checks or
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
- A container must not declare its own nested `Overrides` type. InnoDI 6.0
  rejects that collision instead of emitting a partial, non-mountable API.

## `Lazy<T>` and `Provider<T>`

Use `Lazy<T>` when a factory needs a deferred reference in an acyclic graph.
InnoDI 6.0 rejects cycles containing `Lazy<T>` or `Provider<T>`, even with
`validateDAG: false`: delaying resolution does not break retained ownership.
Move shared state into a separate dependency or restructure the graph.

Use `Provider<T>` when a factory needs to re-enter a `.transient` dependency on
every call.

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
})
var consumer: Consumer
```

```swift
// The synchronous .transient target is named `request`.
@Provide(.shared, factory: { (request: Provider<Request>) in
    RequestLogger(requests: request)
})
var logger: RequestLogger
```

Neither wrapper caches values. `Lazy<T>` follows the target's shared or
transient scope; `Provider<T>` requires a transient target. A transient value
override returns that same stored value on every call, so fresh identity comes
from the live factory, not from the wrapper itself.

Both wrappers are intentionally non-`Sendable` and must stay on the container's
original isolation domain. They also remain synchronous: neither wrapper can
target an `asyncFactory` member.

## Nested Containers and Hierarchy

`@SubContainer` models parent-owned child containers:

```swift
@SubContainer(
    scope: .shared,
    with: [\Self.config, \Self.apiClient],
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
- Parent key paths in `with:` and on the `parent:` side of `bindings:` name one
  direct member as `\Self.member`. A named root such as `\AppContainer.member`
  is rejected with `sub.noncanonical-parent-key-path` and a fix-it, and nested
  components are invalid wiring. The `child:` side names a child input through
  the child container type, which may be module-qualified.
- `featureRoot:` / `featureRoots:` generate SwiftUI root helpers on the parent
  container without stacking another peer macro on the same property.
- Choose exactly one wiring form: `with:` or `bindings:`.
- Parent `Overrides` gain both a full replacement slot (`feature`) and a child
  override closure (`featureOverrides`).

Cross-module ownership uses:

- `@DIContainerRole(role: ContainerRole.component)` for mountable child containers
- `@DIContainerRole(role: ContainerRole.root)` for rooted workspace-level validation

## SwiftUI Helpers

`InnoDISwiftUI` adds a small SwiftUI integration layer on top of the container
contract:

- `.innodi(container)` applies a generated environment bridge to a view tree.
- `@DIEnvironmentBridge` maps container members into SwiftUI environment keys.
- `@SubContainer(..., featureRoot:)` and `featureRoots:` generate default or
  named feature-root helpers for child containers. When `InnoDISwiftUI` is
  imported, pass `identity:` to the generated helper to get lazy host ownership
  without adding a manual State wrapper; the zero-argument helper remains.
- `DIContainerHost` lazily owns fixed or assisted children by route, document,
  or window identity. Applications compose loading/failure/retry UI and call
  its lifecycle handle from the actual close path instead of `onDisappear`.
- `#PreviewWithContainer` uses the same lazy owner and keeps equal preview
  payloads isolated by preview instance.
- InnoDI 5.0 removes the deprecated `@DIFeatureRoot` compatibility macro.
  Replace it with the `@SubContainer` arguments so helper generation stays in
  the container macro pipeline and does not stack peer macros on one property.

Use `@DIContainerRole(role: ContainerRole.local, mainActor: true)` for a local
UI root whose generated API must be main-actor isolated. A component role with
`mainActor: true` also isolates its `<Container>Dependencies` protocol, `init(dependencies:_:)`,
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

Explain graph inclusion, inspect reverse impact, and find containers outside
every explicit root:

```bash
swift run InnoDI-DependencyGraph --root . --why FeatureContainer
swift run InnoDI-DependencyGraph --root . --dependents NetworkContainer
swift run InnoDI-DependencyGraph --root . --why provider:App.AppContainer.client
swift run InnoDI-DependencyGraph --root . --unused
```

Compare two target-scoped JSON graph artifacts:

```bash
swift run InnoDI-DependencyGraph --diff before.json after.json
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
```

`--check-contract` returns exit code 5 when any scope, container, provider, or
edge contract changed, so CI can require an explicitly reviewed graph snapshot
update. Schema v6 provider records include type, lifetime, initialization,
isolation, effect, canonical wiring, and explicit collection contracts; source
line/column movement alone is not a contract change. Older graph schemas are
rejected rather than treated as unchanged. Missing or foreign provider references,
invalid child ownership, and incomplete child input bindings also fail validation,
even when a graph is compared with itself.

Provider selectors are accepted by `--why` and `--dependents`, for example
`--why App.AppContainer.client`. Results include provider contracts and source
locations. Parent dependencies include fixed child and assisted-factory input
bindings on each mount; multiple mounts of the same child remain independent.
Unqualified selectors are resolved against both container and
provider namespaces. A collision fails with both candidate lists; use
`container:<selector>` or `provider:<selector>` to choose explicitly. Exact
graph IDs retain their direct lookup behavior. Runtime cache/override/async
provenance is opt-in through `DITraceContext` and `DIBoundedTraceBuffer`;
disabled tracing allocates no ID, event, or buffer, and events contain no input
values or error payloads. Copy the target ID from the graph artifact into
`DITraceContext(sink:targetIDsByModule:generation:)`, then pass that context to
a generated container's `_innoDITrace:` argument.

Generated eager, on-demand, transient, async, override, cache-hit, and wait
paths now emit automatically. `providerID` matches schema-v6 graph IDs when
the runtime module has a target mapping; otherwise it falls back to the
reflected module-qualified container path. `ownerID` separates container
instances, `generation` separates rebuilds, and `instanceID` joins a start to
its terminal/cache/wait events. Wait events also name the related provider and
instance. InnoDI never introspects tasks started inside a service factory.
Manual instrumentation through `withResolution(providerID:)` and `record`
remains available for non-generated boundaries.

Run the read-only workspace doctor before migration or adoption:

```bash
swift run InnoDI-Doctor --root .
swift run InnoDI-Doctor --root . --json
```

The default mode does not resolve, build, write, delete caches, or stop
processes. For Swift packages, Doctor parses literal target source roots and
plugin arrays, so a comment, string, or another target's plugin cannot hide a
missing attachment. Dynamic manifests and Tuist target mappings remain
explicitly incomplete instead of being reported healthy. Pass the same
`--trust-module <name>` options you give `InnoDI-Migrate` when the migration
check reports `migrate.unqualified-ownership-ambiguous` for your own modules.
`--apply` uses the migrator's preserving atomic-exchange checks. Successful writes retain displaced
files at reported `RECOVERY` paths; review those files after closing editors
before removing them. Doctor schema v3 includes `recoveryPaths`.
SwiftPM `--verify` runs `swift build`; Tuist
verification first runs generation and only runs compilation when `--scheme`
and `--destination` are explicit. Schema-v3 reports keep generation and
compilation exit, timeout, and log-tail evidence separate, so generation alone
is never a successful build.

## Collection Composition

`@Multibinding([])` declares an explicit empty collection. Nonempty arrays use
the generated Swift array as the compiler assignability witness, so concrete
implementations can contribute to existential elements without string-based
type guesses. `DICollectionGroup` and `DIKeyedCollection` compose explicitly
exported module outputs in caller order and reject keyed collisions.
`DIProviderCollection` and `DIKeyedProviderCollection` resolve only a selected
index or key.

Factory-built collections can publish the same closed graph contract with
`@Provide(collection:)`. Use `.ordered`, `.keyed`, `.providers`, or
`.keyedProviders` with literal `\Self.member` contributors; keyed entries use
`.init(key: "id", contributor: \Self.member)`. Explicit empty metadata is valid.
Graph JSON schema v6 records key, order, canonical contributor, and contributor
lifetime without inspecting factory bodies or discovering module members.
Duplicate keys fail instead of using last-wins behavior.

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

Release notes and upgrade notes live in [CHANGELOG.md](CHANGELOG.md).

## Examples

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
- [InnoSample](https://github.com/InnoSquadCorp/InnoSample): a multi-module
  Tuist app that combines InnoDI with InnoFlow, InnoNetwork, and InnoRouter
