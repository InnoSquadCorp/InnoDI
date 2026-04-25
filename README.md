# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

Macro-driven dependency injection for Swift with compile-time and build-time
validation, dependency-graph tooling, hierarchy checks, and SwiftUI helpers.

## Why InnoDI

InnoDI is designed for teams that want DI wiring to stay explicit and
reviewable while moving failure detection earlier.

- `@DIContainer` and `@Provide` generate container APIs from plain Swift types.
- Macro validation catches local mistakes at expansion time.
- Build validation and the graph CLI catch cross-file, cross-module, and global graph issues.
- `InnoDISwiftUI` removes repetitive root-boundary environment wiring.

InnoDI is not a runtime state machine. Runtime state belongs in your app layer
or companion frameworks such as `InnoFlow`, `InnoRouter`, and `InnoNetwork`.

## Requirements

- Swift tools version `6.2`
- Platforms:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### Filesystem requirements for the build-time validator

The build plugin serializes live DAG validation runs through a POSIX
`O_CREAT | O_EXCL` lock file placed under the Swift Package Manager derived
data directory. This works correctly on every local filesystem Apple and
Linux distributions ship today (APFS, HFS+, ext4, btrfs, xfs), but there
are caveats for network-backed paths:

- **NFSv3** does not guarantee atomic `O_EXCL` semantics; two clients can
  both believe they created the lock. Use NFSv4 or relocate derived data
  to a local path.
- **SMB/CIFS** shares do not provide reliable `O_EXCL` atomicity at all
  and are not supported.
- **Docker / Kubernetes bind mounts** inherit the semantics of the host
  filesystem. When the host is local, they are safe.

If your build system must place derived data on a shared volume, point
SPM's `--scratch-path` (or Xcode's derived-data location) at a local
directory before enabling the plugin.

## Installation

Add InnoDI to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.0.0")
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

## Quick Start

```swift
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

    @Provide(.shared, APIClient.self, with: [\.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
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
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

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
original isolation domain.

## Nested Containers and Hierarchy

`@SubContainer` models parent-owned child containers:

```swift
@SubContainer(scope: .shared)
var feature: FeatureContainer
```

Key rules:

- `scope:` is required.
- Parent `@Provide` members are forwarded into the child's `.input` members by
  name.
- `with:` restricts forwarding to an explicit subset.
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
- `@DIFeatureRoot` generates default or named feature-root helpers for child
  containers.

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
