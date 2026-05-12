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
    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## Why InnoDI

InnoDI is designed for teams that want DI wiring to stay explicit and
reviewable while moving failure detection earlier.

- `@DIContainer` and `@Provide` generate container APIs from plain Swift types.
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

- Swift tools version `6.2`
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
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.3.0")
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

Enable the build-time DAG validator by attaching the plugin to each target that
declares InnoDI containers:

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

For teams that have measured source-tool compilation as the dominant adoption
cost, the companion `InnoDIValidationTools` package provides an optional
prebuilt macOS validation plugin. Attach either the source plugin above or the
prebuilt plugin, never both; unsupported hosts and local package development
should keep using the source plugin.

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

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL])
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

All containers synthesize the overrides scaffolding unless the user already
declares a nested `Overrides` type, which suppresses generation.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Meaning |
|---|---|---|
| `root` | `false` | Graph-render entry flag only. If any roots exist, Mermaid, DOT, and ASCII output is pruned to the union of root-reachable nodes and edges. |
| `validateDAG` | `true` | Enables global DAG validation plus the macro's local cycle and closure/`with:` graph-derived checks. `false` skips those checks, but raw-expression `factory:` and initializer references still diagnose at compile time and structural validation still runs. |
| `mainActor` | `false` | Applies `@MainActor` isolation to generated container APIs. Recommended for UI-root containers. |

`@DIContainer` does not support user-defined `init` declarations in the
annotated type or matching extensions. Use the synthesized initializer or wire
the type manually without the macro.

### `@Provide` and scopes

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

| Scope | Meaning | Construction rules |
|---|---|---|
| `.input` | External dependency supplied at container initialization | No `factory` or `asyncFactory` |
| `.shared` | Created once per container instance and reused | Requires `factory`, `asyncFactory`, or `Type.self` plus `with:` |
| `.transient` | Recreated on every access | Requires `factory`, `asyncFactory`, or `Type.self` plus `with:` |

Additional rules:

- `factory` and `asyncFactory` are mutually exclusive.
- `asyncFactory` must be an `async` closure.
- Concrete `.shared` and `.transient` storage requires `concrete: true`.
- Name resolution for factory parameters and `with:` wiring is strict by member name.

## Validation Model

InnoDI validates containers in layers:

1. Macro validation
   - local scope rules
   - missing factories
   - declaration-order checks
   - local cycles
   - invalid `init` declarations
2. Build validation
   - cross-file `init` conflicts
   - semantic reference checks
   - hierarchy validation
   - artifact generation
3. Global DAG validation
   - `swift run InnoDI-DependencyGraph --root . --validate-dag`

`validateDAG: false` is intentionally narrow. It opts a container out of global
DAG validation plus the macro's local cycle and closure/`with:` graph-derived
checks. It does not disable structural validation, and it does not suppress
raw-expression `factory:` or initializer reference diagnostics.

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
- If the container already declares a nested `Overrides` type, the macro emits
  only the primary initializer and skips the generated builder surface.

## `Lazy<T>` and `Provider<T>`

Use `Lazy<T>` when a factory needs a deferred reference that should be excluded
from cycle detection.

Use `Provider<T>` when a factory needs to re-enter a `.transient` dependency on
every call.

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
}, concrete: true)
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
}, concrete: true)
var logger: RequestLogger
```

Both wrappers are intentionally non-`Sendable` and must stay on the container's
original isolation domain.

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
- `@DIFeatureRoot` remains as a deprecated compatibility macro; new code
  should use the `@SubContainer` arguments so helper generation stays in the
  container macro pipeline.

Use `@DIContainer(mainActor: true)` for UI-root containers when you want the
generated container API isolated to the main actor.

## CLI and Release Surface

Render a graph:

```bash
swift run InnoDI-DependencyGraph --root .
```

Validate the global DAG:

```bash
swift run InnoDI-DependencyGraph --root . --validate-dag
```

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
