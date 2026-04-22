# InnoDI

[English](README.md) | [한국어](README.ko.md)

A Swift Macro-based Dependency Injection library for clean, type-safe DI containers.

## State Ownership

InnoDI is a **static dependency graph and scope validation** framework.

- Use `DIScope` to describe construction lifetime.
- Use DAG validation and diagnostics to catch graph problems early.
- Do not treat container resolution as a runtime state machine.

Across the InnoSquad stack, runtime state transitions belong in `InnoFlow`,
navigation transitions belong in `InnoRouter`, and transport/session lifecycle
belongs in `InnoNetwork`.

## Features

- **Compile-time safety**: Macro-based validation catches errors at build time
- **Zero boilerplate**: Auto-generated initializers with optional override parameters
- **Multiple scopes**: `shared`, `input`, and `transient` lifecycle management
- **AutoWiring**: Simplified syntax with `Type.self` and `with:` dependencies
- **Strict name-based resolution**: Factory parameters and `with:` dependencies resolve by member name only
- **Init Override**: Direct mock injection via init parameters, plus a named `Overrides` builder with a trailing-closure convenience init and `withOverrides` helpers
- **Optional hierarchy layer**: `@DIComponent` + `@DIHierarchyRoot` add rooted cross-module ownership validation without changing same-module `@DIContainer` ergonomics
- **Protocol-first design**: Encourage DIP compliance with `concrete` opt-in

## Installation

Add InnoDI to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "3.0.1")
]
```

Then add it to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["InnoDI"]
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
    func fetch() async throws -> Data { /* ... */ }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\.baseURL])
    var apiClient: any APIClientProtocol
}

// Usage
let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
```

For more control, use factory closures instead:

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL, timeout: 30)
})
var apiClient: any APIClientProtocol
```

## Start Here

If you are new to InnoDI, read the docs in this order:

1. This README for installation, container syntax, and the supported model.
2. [Validation](Sources/InnoDI/InnoDI.docc/Validation.md) for local/build/global validation and observability artifacts.
3. [PolicyBoundaries](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md) for exact matching rules, exclusions, and fallback behavior.
4. [ModuleWideInitDetection](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md) for the custom `init` restriction model.

Release and maintenance references:

- [CHANGELOG.md](CHANGELOG.md)
- [RELEASING.md](RELEASING.md)
- [MIGRATION.md](MIGRATION.md)

## API Reference

### `@DIContainer`

Marks a struct as a DI container. Generates:

1. A primary `init(...)` with required `.input` parameters and optional overrides for `.shared` / `.transient` members.
2. When the container declares any `.shared`, `.transient`, or `@SubContainer` member, a nested `struct Overrides` (see [Testing with the Overrides builder](#testing-with-the-overrides-builder)).
3. A convenience `init(<inputs…>, _ applyOverrides: (inout Overrides) -> Void)` that funnels named overrides into the primary init.
4. Four `static func withOverrides<T>(<inputs…>, _ applyOverrides:, operation:)` effect overloads — `sync` / `throws` / `async` / `async throws` — that build a scoped container and run an operation against it.

All containers synthesize the overrides scaffolding unless the user declares their own nested `Overrides` type, which suppresses generation (see [User-defined Overrides conflict](#user-defined-overrides-conflict)).

`@DIContainer` does not support user-defined `init` declarations in the annotated type or any extension.
Macro validation rejects body and same-file extension `init` declarations, and the build plugin extends the same rule to cross-file extensions. Boundary details such as generic/constrained exclusions and conservative fallback rules are documented in `PolicyBoundaries`.
Use the synthesized initializer, or remove the macro and wire the type manually.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `root` | `false` | Mark container as root in graph rendering. |
| `validateDAG` | `true` | Enable local/global DAG validation for this container. Set `false` to opt out from DAG checks. |
| `mainActor` | `false` | Apply `@MainActor` isolation to generated container APIs. Recommended for SwiftUI/UI-root containers under strict concurrency. |

### `@Provide`

Declares a dependency with its scope and factory.

```swift
@Provide(_ scope: DIScope = .shared, _ type: Type.self? = nil, with: [KeyPath] = [], factory: Any? = nil, asyncFactory: Any? = nil, concrete: Bool = false)
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `scope` | `.shared` | Lifecycle scope (see below) |
| `type` | `nil` | Concrete type for AutoWiring (alternative to factory) |
| `with` | `[]` | Dependencies to inject via AutoWiring |
| `factory` | `nil` | Factory expression (required for `.shared` and `.transient` if no type) |
| `asyncFactory` | `nil` | Async factory closure (mutually exclusive with `factory`) |
| `concrete` | `false` | Required opt-in when the dependency property type is concrete (see DIP section) |

### `@DIComponent`

```swift
@DIComponent
@DIContainer
public struct FeatureContainer {
    @Provide(.input) public var config: FeatureConfig
}
```

Marks a `@DIContainer` as a cross-module mountable component. InnoDI lifts the
child's `.input` members into a generated `<ContainerName>Dependencies`
protocol and also synthesizes `init(dependencies:_:)` so parent modules can
mount the child through an explicit dependency contract.

### `@DIHierarchyRoot`

```swift
@DIHierarchyRoot
@DIContainer(root: true)
struct AppContainer {
    @Provide(.input) var config: AppConfig
    @SubContainer(scope: .shared) var feature: FeatureContainer
}
```

Marks a root container that enables strict workspace-level hierarchy
validation. When at least one hierarchy root exists, build validation also
checks:

- cross-module children must be marked `@DIComponent`
- parent modules must satisfy child `.input` contracts
- each component must have a single parent
- rooted ownership cycles are rejected

### `DIScope`

| Scope | Description | Factory Required |
|-------|-------------|------------------|
| `.input` | Provided at container initialization | No |
| `.shared` | Created once, cached for container lifetime | Yes |
| `.transient` | New instance created on every access | Yes |

Scope laws:
- `.input` is external data and must come from container initialization.
- `.shared` is stable for one container instance and should be reused on repeated access.
- `.transient` must produce fresh instances and should not be treated as cached state.

### Async Factory

Use `asyncFactory` when construction is asynchronous:

```swift
@Provide(.shared, asyncFactory: { (config: AppConfig) async throws in
    try await APIClient.make(config: config)
})
var apiClient: any APIClientProtocol
```

Rules:

- `factory` and `asyncFactory` cannot be used together.
- `.input` scope does not allow `asyncFactory`.
- `asyncFactory` must be declared as an `async` closure.

## Scopes in Detail

### `.input` - External Dependencies

Use for values that must be provided when creating the container:

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: AppConfig

    @Provide(.input)
    var analytics: AnalyticsService
}

let container = AppContainer(
    config: AppConfig(env: .production),
    analytics: FirebaseAnalytics()
)
```

### `.shared` - Singleton per Container

Use for services that should be instantiated once and reused:

```swift
@DIContainer
struct AppContainer {
    @Provide(.shared, factory: URLSession.shared)
    var session: any URLSessionProtocol

    @Provide(.shared, factory: NetworkService(session: session))
    var networkService: any NetworkServiceProtocol
}
```

### `.transient` - Fresh Instance Every Time

Use for objects that need a new instance on each access (e.g., ViewModels):

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var apiClient: any APIClientProtocol

    @Provide(.transient, factory: HomeViewModel(api: apiClient))
    var homeViewModel: HomeViewModel

    @Provide(.transient, factory: ProfileViewModel(api: apiClient))
    var profileViewModel: ProfileViewModel
}

// Each access creates a new instance
let vm1 = container.homeViewModel  // New instance
let vm2 = container.homeViewModel  // Another new instance
```

## AutoWiring

For simpler cases, use `Type.self` with `with:` instead of verbose factory closures:

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: AppConfig

    @Provide(.input)
    var logger: Logger

    // AutoWiring: APIClient(config: self.config, logger: self.logger)
    @Provide(.shared, APIClient.self, with: [\.config, \.logger])
    var apiClient: any APIClientProtocol
}
```

**Requirements**:
- The property names in `with:` must match the init parameter names of the concrete type
- Example: `APIClient(config:logger:)` matches `with: [\.config, \.logger]`

**When to use factory closure instead**:
- Parameter names don't match property names
- Complex initialization logic needed
- Need to transform dependencies

```swift
// Factory closure for complex cases
@Provide(.shared, factory: { (config: AppConfig) in
    APIClient(configuration: config, timeout: 30)
})
var apiClient: any APIClientProtocol
```

## Dependency Inversion Principle (DIP)

InnoDI enforces protocol-first dependencies for `.shared` and `.transient`.
Use explicit existential syntax (`any Protocol`) for protocol-typed dependencies.
If you need to use a concrete type, explicitly opt-in with `concrete: true`:

```swift
@DIContainer
struct AppContainer {
    // Preferred: Protocol type
    @Provide(.shared, factory: APIClient())
    var apiClient: any APIClientProtocol

    // Allowed: Concrete type with explicit opt-in
    @Provide(.shared, factory: URLSession.shared, concrete: true)
    var session: URLSession
}
```

This makes concrete type usage intentional and visible in code review.

## Init Override (Testing)

The generated init accepts optional parameters for `.shared` and `.transient` dependencies, allowing direct mock injection:

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, factory: APIClient(baseURL: baseURL))
    var apiClient: any APIClientProtocol
}

// Production - factory creates the instance
let container = AppContainer(baseURL: "https://api.example.com")

// Testing - directly inject mock
let testContainer = AppContainer(
    baseURL: "https://test.example.com",
    apiClient: MockAPIClient()  // Override with mock!
)
```

Generated init signature:
```swift
init(baseURL: String, apiClient: (any APIClientProtocol)? = nil)
```

- `.input` parameters are required
- `.shared` and `.transient` parameters are optional with `nil` default
- When `nil`, the factory creates the instance; when provided, uses the injected value

## Testing with the Overrides builder

Positional overrides on the generated init work, but they force every test to
restate every optional parameter. For containers with any `.shared` or
`.transient` member, `@DIContainer` additionally emits a named builder so tests
only touch the members they actually want to replace.

### Convenience init with a trailing closure

Use the trailing-closure convenience init when you want to hold on to the
container yourself:

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, factory: { APIClient(baseURL: baseURL) })
    var apiClient: any APIClientProtocol

    @Provide(.transient, factory: { (apiClient: any APIClientProtocol) in
        HomeViewModel(api: apiClient)
    }, concrete: true)
    var homeViewModel: HomeViewModel
}

let container = AppContainer(baseURL: "https://test.example.com") {
    $0.apiClient = MockAPIClient()
}
// container.apiClient is MockAPIClient
// container.homeViewModel resolves through the mocked apiClient
```

Only the members you set on the builder are overridden; the rest still flow
through the original factories. Shared overrides cascade: downstream
`.transient` factories that read the shared member observe the mock.

### `withOverrides` scoped operation

When you want override lifetime bound to a single operation — mirroring
`swift-dependencies`' `withDependencies { } operation:` style — use the
generated `static withOverrides`:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.homeViewModel.load()
}
```

Four overloads are generated for every effect shape, so you never have to
`try await` a synchronous callsite:

| Overload | Signature shape |
|---|---|
| sync, non-throwing | `(Container) -> T` |
| sync, throwing | `(Container) throws -> T` |
| async, non-throwing | `(Container) async -> T` |
| async, throwing | `(Container) async throws -> T` |

All generated builder surfaces inherit the container's access level (`public`
containers produce `public` builders) and propagate `@MainActor` when the
container is main-actor isolated.

### Async `.shared` overrides

Async-factory `.shared` members appear on the builder as plain optional values
(`var apiClient: APIClient? = nil`), *not* as `Task<APIClient, …>?`. The
generated init still wraps the resolved value in the same task-backed accessor
used in production — overriding just short-circuits the factory with the value
you supplied.

### `.transient` overrides return the stored value

Setting a `.transient` override returns **that exact value** on every access
of the accessor (overrides bypass the per-access factory). This matches the
convenience init's semantics and makes it trivial to pin a single value for
assertion.

### User-defined `Overrides` conflict

If your container already declares a nested `Overrides` type (`struct`,
`class`, `enum`, `actor`, or `typealias`), the macro emits the
`container.overrides-name-conflict` warning and **skips generating** the
`Overrides` struct, the convenience init, and the `withOverrides` overloads —
the primary init is unchanged. Rename your type to restore the builder API, or
leave it in place to keep your own implementation.

## Cycle breaking with `Lazy<T>`

`@DIContainer` enforces a strict dependency DAG: if container A's factory
references B and B's factory references A, the macro emits
`container.dependency-cycle` and fails to compile. Most cycles are a sign to
restructure the graph, but some are intrinsic — coordinator ↔ view model,
parent ↔ child scene, etc. — and the idiomatic fix elsewhere in the
ecosystem is to defer one side of the edge.

InnoDI ships `Lazy<T>` for exactly this case:

```swift
import InnoDI

@DIContainer
struct AppContainer {
    @Provide(.shared, factory: { (b: InnoDI.Lazy<CoordinatorB>) in CoordinatorA(b: b) }, concrete: true)
    var a: CoordinatorA

    @Provide(.shared, factory: { (a: CoordinatorA) in CoordinatorB(a: a) }, concrete: true)
    var b: CoordinatorB
}

final class CoordinatorA {
    let b: InnoDI.Lazy<CoordinatorB>
    init(b: InnoDI.Lazy<CoordinatorB>) { self.b = b }
    func resolveB() -> CoordinatorB { b() }
}

final class CoordinatorB {
    let a: CoordinatorA
    init(a: CoordinatorA) { self.a = a }
}
```

### How it works

- `Lazy<T>` wraps a plain `() -> T` resolver. Calling `b()` returns the
  eventually-resolved instance; InnoDI does no extra caching inside the
  wrapper (the container's `.shared` scope already caches).
- `Lazy<T>` is intentionally **non-Sendable**. It keeps deferred resolution
  on the container's original isolation domain, so actor-boundary transport
  is not supported even when the payload itself is `Sendable`.
- A factory parameter typed `Lazy<T>` is classified as a **soft** dependency.
  Soft edges are excluded from both the per-container cycle detector and
  the CLI `--validate-dag` gate, but still appear in the generated graph.
- Generated init code allocates one `_LazyCell<T>` per soft-target member at
  init start, passes the written `Lazy` form (for example `InnoDI.Lazy`)
  as `Lazy({ cell.resolve() })` into the factory, then either stores the
  concrete shared/input value or binds a transient resolver after init.
  That lets struct containers forward-reference siblings without capturing
  `self` during the factory call.
- The container member that owns the `Lazy<T>` resolver must be declared
  *before* its target so the `_LazyCell` exists when the factory runs.
- The `container.dependency-cycle` diagnostic now ends with
  _"To break this cycle without restructuring, wrap one factory parameter in `Lazy<T>`."_

### Caveats

- Detection is textual: `Lazy<Foo>`, `InnoDI.Lazy<Foo>`, and member-qualified
  `Something.Lazy<Foo>` all trigger the soft-edge path. A `typealias Lazy
  = MyOwnType` will **not** be recognized — the macro does not resolve
  aliases. Generated wrappers preserve the written qualifier, so the
  supported collision-safe spelling is `InnoDI.Lazy<Foo>`. See
  [MIGRATION.md](MIGRATION.md) if you own a colliding top-level `Lazy<T>`.
- `Lazy<T>` is fine with `.transient` — each `a()` call produces a fresh
  instance from the factory. `Lazy<Self>` is accepted; whether it makes
  sense at runtime depends on your factory (a self-referential `.transient`
  will recurse).
- `Lazy<T>` remains synchronous, so it cannot target `.shared` members that
  are produced by `asyncFactory`.

## Fresh transients with `Provider<T>`

When a `.shared` service needs repeated access to a `.transient` dependency —
think request loggers, retry workers, per-message processors — injecting the
transient directly would freeze one instance at construction. `Provider<T>`
gives the consumer a handle that re-enters the container's transient accessor
on every call.

```swift
import InnoDI

@DIContainer
struct AppContainer {
    @Provide(.input) var config: Config

    @Provide(.transient, factory: { (config: Config) in Request(config: config) }, concrete: true)
    var request: Request

    @Provide(.shared, factory: { (requests: Provider<Request>) in
        RequestLogger(requests: requests)
    }, concrete: true)
    var logger: RequestLogger
}

final class RequestLogger {
    let requests: Provider<Request>
    init(requests: Provider<Request>) { self.requests = requests }
    func logNew() { let request = requests(); _ = request }  // re-enters `.transient`; overrides may reuse a stored value
}
```

### Provider vs Lazy

Both wrappers defer resolution, but they address different needs:

| Need | Wrapper | Behaviour |
|---|---|---|
| Break a `.shared ↔ .shared` cycle by deferring one side | `Lazy<T>` | First `resolver()` call returns the target; container's `.shared` scope decides caching. |
| Re-enter a `.transient` accessor on demand | `Provider<T>` | Every `resolver()` call re-enters the transient accessor; overrides may return stored values. |

The macro classifies `Provider<T>` factory parameters as a distinct
*provider edge* — excluded from cycle detection (like `Lazy<T>`) but rendered
with its own style in the CLI graph (thick `==>` in Mermaid, `style=dotted`
in DOT, `~~>` in ASCII with a legend).

`Provider<T>` matches `Lazy<T>`'s concurrency contract: it is an intentionally
non-`Sendable` deferred handle that keeps transient re-entry on the
container's original isolation domain.

### Validation rules

- The target member **must** be `.transient`. A `Provider<T>` factory
  parameter whose target is `.shared` or `.input` fails with
  `provide.provider-non-transient-target`. This keeps the "fresh instance
  per live call" contract honest while still allowing override-backed tests
  to return stored values — if you want caching, use `Lazy<T>` instead.
- The target may be declared *after* the factory that consumes the
  `Provider<T>` handle. Like `Lazy<T>`, provider edges escape declaration-
  order availability checks.

### Caveats

- Detection is textual, like `Lazy<T>`. `Provider<Foo>`, `InnoDI.Provider<Foo>`,
  and member-qualified `Something.Provider<Foo>` are all recognized;
  typealiases are not. Generated wrappers preserve the written qualifier.
- Do not call a `Provider<T>` directly inside a `.shared` factory or
  `asyncFactory` body. Treat it like a handle to store or pass onward, then
  invoke only after container initialization completes. InnoDI now diagnoses
  direct `provider()` / `provider.callAsFunction()` syntax in shared
  construction, but indirect helper-based eager calls can still resolve too
  early.
- Shared initialization paths that forward a deferred target still reuse
  InnoDI's `_LazyCell` late-binding box. Transient-accessor-only
  `Provider<T>` / `Lazy<T>` paths capture `self` directly inside the wrapper,
  which is why those handles intentionally remain non-`Sendable`.

## Strict concurrency notes

- Prefer `@DIContainer(mainActor: true)` for SwiftUI or other UI-facing root
  containers.
- `Lazy<T>` / `Provider<T>` are intentionally non-`Sendable`; do not move
  them across actors or store them in `Sendable` types.
- InnoDI still hardens transient sub-container builders and init-time
  late-binding storage for strict concurrency, but a container only conforms
  to `Sendable` when its own stored members and override closures satisfy
  Swift's rules.

## Nested containers with `@SubContainer`

Some dependency graphs are naturally hierarchical: an app container owns
per-screen or per-request sub-containers that share its configuration but
have their own local `.shared` state. `@SubContainer` lets the parent
declare and own those children directly, so callers read `app.feature`
instead of re-wiring every `.input` by hand.

```swift
import InnoDI

@DIContainer(root: true)
struct AppContainer {
    @Provide(.input) var config: AppConfig
    @Provide(.shared, factory: APIClient())
    var apiClient: any APIClientProtocol

    @SubContainer(scope: .shared)
    var feature: FeatureContainer
}

@DIContainer
struct FeatureContainer {
    @Provide(.input) var config: AppConfig
    @Provide(.input) var apiClient: any APIClientProtocol

    @Provide(.shared, factory: FeatureStore(), concrete: true)
    var store: FeatureStore
}

let app = AppContainer(config: .init(...))
let feature = app.feature  // child wired automatically from parent members
```

### Scope

`@SubContainer` requires an explicit scope because the two lifetimes have
very different runtime behaviour:

| `scope:` | Behaviour | Use when |
|---|---|---|
| `.shared` | Parent builds the child once during init, stores it, and reuses it on every read. | The child should behave like a long-lived coordinator whose inner `.shared` graph is stable across views. |
| `.transient` | Every read of `app.feature` builds a fresh child. | Per-screen / per-request scopes — each caller gets an independent child with its own `.shared` instances. |

### Wiring rules

- **Auto-match by name.** By default every `@Provide` on the parent is
  forwarded positionally: `FeatureContainer(config: self.config,
  apiClient: self.apiClient)`. The child's `.input` parameter labels
  must match parent member names. If they don't, Swift raises a normal
  compile error at the generated call site.
- **`with: [\.parentName]`** restricts the forwarded set to a specific
  subset — useful when the child only needs a few of the parent's
  members. The macro still labels each argument by parent-member name;
  it does not rewrite labels.
- **`.shared` sub cannot read `.transient` parents.** `.shared`
  children are built inside the parent init, where `.transient`
  accessors are not yet callable. The validator rejects that
  combination with `sub.shared-parent-must-not-be-transient`.

### Overrides builder integration

Every `@SubContainer` member adds two slots to the parent's
`Overrides` struct:

| Slot | Meaning |
|---|---|
| `var <name>: <ChildContainer>? = nil` | Replace the child entirely (e.g. inject a mock sub-container). |
| `var <name>Overrides: ((inout <ChildContainer>.Overrides) -> Void)? = nil` | Chain into the child's own convenience init so individual `.shared`/`.transient` members can be overridden per test. |

Direct replacement wins when both slots are set. The chain closure
requires the child to have its own `Overrides` builder (i.e. at least
one `.shared` / `.transient` / `@SubContainer` member on the child).
This is a compile-time constraint even if you never set
`overrides.<name>Overrides`: the parent's generated init and `Overrides`
struct both reference `<ChildContainer>.Overrides` in their type
signatures. An input-only child therefore causes the parent to fail with
the usual `type '<ChildContainer>' has no member 'Overrides'` compile
error. Remedy: add at least one `.shared`, `.transient`, or
`@SubContainer` member to the child so InnoDI emits
`<ChildContainer>.Overrides`.

```swift
let container = AppContainer(config: .init(...)) { overrides in
    overrides.featureOverrides = { feature in
        feature.store = MockStore()
    }
}

let tag = AppContainer.withOverrides(config: .init(...)) { overrides in
    overrides.feature = MockFeatureContainer(...)     // full replacement
} operation: { app in
    app.feature.readSomething()
}
```

### Validation diagnostics

| Code | Fires when |
|---|---|
| `sub.scope-required` | `@SubContainer` without a `scope:` argument. |
| `sub.unknown-scope` | Scope value is not `.shared` / `.transient`. |
| `sub.conflicts-with-provide` | Same property carries both `@Provide` and `@SubContainer`. |
| `sub.unknown-parent-member` | `with:` keypath does not resolve to a `@Provide` member on the parent. |
| `sub.shared-parent-must-not-be-transient` | `.shared` sub-container would read a parent member that has `.transient` scope. |

### Graph rendering

The CLI recognises `@SubContainer` as an ownership relationship and
renders it with its own style so reviewers can distinguish ownership
from regular `.input` wiring:

| Format | Ownership glyph |
|---|---|
| Mermaid | `-->` with forced `owns: <member>` label |
| DOT | `style=bold, color="#1e3a8a"` |
| ASCII | `#=>` glyph with `:owns,<member>` suffix + legend row |

Ownership edges participate in cycle detection as hard edges — child
construction happens at parent-init time, so a parent ↔ child loop
would loop during init.

## Dependency Graph Visualization

InnoDI includes a command-line tool to generate dependency graphs from your `@DIContainer` declarations. This helps visualize the relationships between containers and their dependencies.

### Installation

The CLI tool is included when you add InnoDI to your project. You can run it via Swift Package Manager:

```bash
swift run InnoDI-DependencyGraph --help
```

### Usage

Generate a Mermaid diagram (default):

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project
```

Generate a DOT file for Graphviz:

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.dot
```

Generate a PNG image directly (requires Graphviz installed):

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --format dot --output graph.png
```

Validate global DAG (fails on cycle and ambiguous container references):

```bash
swift run InnoDI-DependencyGraph --root /path/to/your/project --validate-dag
```

### Options

- `--root <path>`: Root directory of the project (default: current directory)
- `--format <mermaid|dot|ascii>`: Output format (default: mermaid)
- `--output <file>`: Output file path (default: stdout)
- `--validate-dag`: Validate global container DAG and fail on cycle/ambiguity

### Validation Notes

- Containers annotated with `@DIContainer(validateDAG: false)` are fully excluded from global DAG validation (`--validate-dag`), including cycle and ambiguity checks.
- Macro-level dependency extraction for cycle validation is AST-based, so string literal tokens no longer produce false-positive dependency edges.

### DocC API Documentation

Generate local DocC docs:

```bash
Tools/generate-docc.sh
```

Online DocC (GitHub Pages):

- https://innosquadcorp.github.io/InnoDI/documentation/innodi/

CI behavior from `.github/workflows/docs.yml`:

- `pull_request`: uploads `innodi-docc` artifact for preview/download.
- `push` to `main`: deploys DocC site to GitHub Pages.

If this is your first Pages deployment, set repository Pages source to `GitHub Actions`
in repository settings.

### Build Tool Plugin (DAG Validation)

InnoDI ships a SwiftPM build tool plugin:

- `InnoDIDAGValidationPlugin`

The plugin coordinates validation once per package input state and reuses the shared result across targets,
instead of rescanning the package graph independently for every target.

Attach it to your app target to fail builds when DAG validation fails:

```swift
.target(
    name: "YourApp",
    dependencies: ["InnoDI"],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

### Extended Examples

See runnable examples in `/Examples`:

- `/Examples/SwiftUIExample` - `InnoDISwiftUI` shows `.innodi(container)` root wiring plus multi-root `@DIFeatureRoot` helpers for a shared `@SubContainer`
- `/Examples/PreviewInjectionExample` - live, preview, and failure roots reuse the generated SwiftUI environment bridge while rendering a richer preview matrix
- `/Examples/SampleApp`

### Example Output

```
graph TD
    AppContainer[root]
    RepositoryContainer
    UseCaseContainer
    RemoteDataSourceContainer
    FeatureContainer
    ThirdPartyContainer
    CoreContainer
    AppContainer -->|loginBuilder| FeatureContainer
    AppContainer --> RemoteDataSourceContainer
```

## Macro Performance Check

Use the included script to detect macro test performance regressions:

```bash
Tools/measure-macro-performance.sh
```

Update baseline after intentional performance changes:

```bash
Tools/measure-macro-performance.sh --iterations 5 --update-baseline
```

Default baseline file:

- `Tools/macro-performance-baseline.json`

## License

MIT

See [LICENSE](LICENSE).
