# InnoDI

[English](README.md) | [한국어](README.ko.md)

A Swift Macro-based Dependency Injection library for clean, type-safe DI containers.

## Features

- **Compile-time safety**: Macro-based validation catches errors at build time
- **Zero boilerplate**: Auto-generated initializers with optional override parameters
- **Multiple scopes**: `shared`, `input`, and `transient` lifecycle management
- **AutoWiring**: Simplified syntax with `Type.self` and `with:` dependencies
- **Init Override**: Direct mock injection via init parameters (no separate Overrides struct)
- **Protocol-first design**: Encourage DIP compliance with `concrete` opt-in

## Installation

Add InnoDI to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "1.0.0")
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

## API Reference

### `@DIContainer`

Marks a struct as a DI container. Generates `init(...)` with optional override parameters.

```swift
@DIContainer(validate: Bool = true, root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `validate` | `true` | Enable compile-time scope/factory validation. `false` relaxes missing-factory checks for `.shared`/`.transient` and emits runtime `fatalError` fallback for missing `.shared` and `.transient` factories. `.input` factory prohibition and concrete opt-in remain enforced. |
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

CI publishes DocC artifacts from `.github/workflows/docs.yml`.

### Build Tool Plugin (DAG Validation)

InnoDI ships a SwiftPM build tool plugin:

- `InnoDIDAGValidationPlugin`

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

- `/Examples/SwiftUIExample`
- `/Examples/TCAIntegrationExample`
- `/Examples/PreviewInjectionExample`
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
