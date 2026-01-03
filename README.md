# InnoDI

A Swift Macro-based Dependency Injection library for clean, type-safe DI containers.

## Features

- **Compile-time safety**: Macro-based validation catches errors at build time
- **Zero boilerplate**: Auto-generated initializers and override structs
- **Multiple scopes**: `shared`, `input`, and `transient` lifecycle management
- **Protocol-first design**: Encourage DIP compliance with `concrete` opt-in
- **Static analysis CLI**: Detect missing dependencies and orphan containers

## Installation

Add InnoDI to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/InnoDI.git", from: "1.0.0")
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

    @Provide(.shared, factory: APIClient(baseURL: baseURL))
    var apiClient: APIClientProtocol
}

// Usage
let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
```

## API Reference

### `@DIContainer`

Marks a struct as a DI container. Generates `init(...)` and `Overrides` struct.

```swift
@DIContainer(validate: Bool = true, root: Bool = false)
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `validate` | `true` | Enable compile-time validation |
| `root` | `false` | Mark as root container for CLI analysis |

### `@Provide`

Declares a dependency with its scope and factory.

```swift
@Provide(_ scope: DIScope = .shared, factory: Any? = nil, concrete: Bool = false)
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `scope` | `.shared` | Lifecycle scope (see below) |
| `factory` | `nil` | Factory expression (required for `.shared` and `.transient`) |
| `concrete` | `false` | Opt-in for concrete type usage (see DIP section) |

### `DIScope`

| Scope | Description | Factory Required |
|-------|-------------|------------------|
| `.input` | Provided at container initialization | No |
| `.shared` | Created once, cached for container lifetime | Yes |
| `.transient` | New instance created on every access | Yes |

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
    var session: URLSessionProtocol

    @Provide(.shared, factory: NetworkService(session: session))
    var networkService: NetworkServiceProtocol
}
```

### `.transient` - Fresh Instance Every Time

Use for objects that need a new instance on each access (e.g., ViewModels):

```swift
@DIContainer
struct AppContainer {
    @Provide(.input)
    var apiClient: APIClientProtocol

    @Provide(.transient, factory: HomeViewModel(api: apiClient))
    var homeViewModel: HomeViewModel

    @Provide(.transient, factory: ProfileViewModel(api: apiClient))
    var profileViewModel: ProfileViewModel
}

// Each access creates a new instance
let vm1 = container.homeViewModel  // New instance
let vm2 = container.homeViewModel  // Another new instance
```

## Dependency Inversion Principle (DIP)

InnoDI encourages protocol-based dependencies. If you need to use a concrete type, explicitly opt-in with `concrete: true`:

```swift
@DIContainer
struct AppContainer {
    // Preferred: Protocol type
    @Provide(.shared, factory: APIClient())
    var apiClient: APIClientProtocol

    // Allowed: Concrete type with explicit opt-in
    @Provide(.shared, factory: URLSession.shared, concrete: true)
    var session: URLSession
}
```

This makes concrete type usage intentional and visible in code review.

## Overrides (Testing)

The macro generates an `Overrides` struct for dependency substitution:

```swift
// Production
let container = AppContainer(baseURL: "https://api.example.com")

// Testing
var overrides = AppContainer.Overrides()
overrides.apiClient = MockAPIClient()
let testContainer = AppContainer(overrides: overrides, baseURL: "https://test.example.com")
```

## CLI Static Analysis

Detect dependency issues at build time:

```bash
swift run InnoDICLI --root /path/to/your/project
```

Reports:
- Missing required `.input` arguments
- Containers not reachable from root containers

Mark root containers for analysis:

```swift
@DIContainer(root: true)
struct AppContainer { ... }
```

## Examples

See [`Examples/README.md`](Examples/README.md) for runnable examples:

1. DI + Macro Usage
2. CLI Usage (Static Analysis)
3. Core Parsing Tests
4. Macro Expansion Tests

## License

MIT
