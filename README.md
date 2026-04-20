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
2. When the container declares any `.shared` or `.transient` member, a nested `struct Overrides` (see [Testing with the Overrides builder](#testing-with-the-overrides-builder)).
3. A convenience `init(<inputs…>, _ applyOverrides: (inout Overrides) -> Void)` that funnels named overrides into the primary init.
4. Four `static func withOverrides<T>(<inputs…>, _ applyOverrides:, operation:)` effect overloads — `sync` / `throws` / `async` / `async throws` — that build a scoped container and run an operation against it.

Input-only containers, and containers where the user declares their own nested `Overrides` type, skip the scaffolding (see [User-defined Overrides conflict](#user-defined-overrides-conflict)).

`@DIContainer` does not support user-defined `init` declarations in the annotated type or any extension.
Macro validation rejects body and same-file extension `init` declarations, and the build plugin extends the same rule to cross-file extensions. Boundary details such as generic/constrained exclusions and conservative fallback rules are documented in `PolicyBoundaries`.
Use the synthesized initializer, or remove the macro and wire the type manually.

```swift
@DIContainer(validate: Bool = true, root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `validate` | `true` | Reserved compatibility flag. Core construction invariants such as `.shared`/`.transient` factory requirements, `.input` restrictions, and `concrete: true` opt-in remain compile-time enforced. |
| `root` | `false` | Mark container as root in graph rendering. |
| `validateDAG` | `true` | Enable local/global DAG validation for this container. Set `false` to opt out from DAG checks. |
| `mainActor` | `false` | Apply `@MainActor` isolation to generated initializer/accessors. |

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

- `Lazy<T>` wraps a `@Sendable () -> T` resolver. Calling `b()` returns the
  eventually-resolved instance; InnoDI does no extra caching inside the
  wrapper (the container's `.shared` scope already caches).
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

- `/Examples/SwiftUIExample` - a single feature root demonstrates navigation, loading skeletons, recoverable error/retry flow, and cancellation around local `@Observable` state
- `/Examples/TCAIntegrationExample`
- `/Examples/PreviewInjectionExample` - live, preview, and failure roots render a richer preview matrix by swapping multiple services at the environment boundary
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

## Benchmarks

Run benchmark suites (10/50/100/250 dependencies):

```bash
Benchmarks/run-compile-bench.sh
Benchmarks/run-runtime-bench.sh
Benchmarks/compare.sh
```

Output JSON files:

- `Benchmarks/results/compile.json`
- `Benchmarks/results/runtime.json`
- `Benchmarks/results/compare.json`

Needle/SafeDI sections are currently scaffolded as non-blocking comparison slots in the report.

Update baseline after intentional performance changes:

```bash
Tools/measure-macro-performance.sh --iterations 5 --update-baseline
```

Default baseline file:

- `Tools/macro-performance-baseline.json`

## License

MIT

See [LICENSE](LICENSE).
