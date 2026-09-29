# Migrating from Factory

Move registrations from a runtime Factory container into a generated InnoDI
container.

## Overview

Factory resolves dependencies at runtime from a shared container, usually
through key-path property wrappers such as `@Injected(\.service)`. InnoDI
generates a container initializer instead and validates the dependency graph
while the macro expands and the build plugin runs. Migration therefore moves
two things: registrations become `@Provide` members of a `@DIContainer`, and
resolution becomes explicit initializer or factory-closure parameters.

InnoDI intentionally has no `@Injected` property wrapper, no process-global
container, and no runtime registration API. A type receives its dependencies
through its initializer, and the composition root owns the container value.

## Concept Map

| Factory 3 | InnoDI |
|---|---|
| `extension Container { var api: Factory<API> { self { LiveAPI() } } }` | `@Provide(.transient, factory: LiveAPI()) var api: any API` |
| Default `.unique` scope | `.transient` |
| `.singleton` | `.shared` on the root container that the app creates once. InnoDI has no process-global scope; the container instance is the lifetime. |
| `.cached` and `Container.shared.reset()` | `.shared`; construct a new container to start over |
| `.shared` (weakly held) | No equivalent. InnoDI holds strong references. |
| `.graph` | `.shared` members of a `.transient` `@SubContainer`, which builds one child per read |
| `@Injected(\.api) var api` | An initializer parameter, supplied by a factory-closure parameter such as `{ (api: any API) in ViewModel(api: api) }` |
| `Container.shared.api()` | `container.api` at the composition root |
| `Container.shared.api.register { MockAPI() }` | `AppContainer(...) { $0.api = MockAPI() }` or `AppContainer.withOverrides(...)` |
| `.onTest { }` and `.onPreview { }` | Separate test and preview containers built with the generated `Overrides`. Mark live providers `effect: .sideEffect` and validate presets with `InnoDITesting`. |
| `ParameterFactory<P, T>` | `@Input(.assisted)` plus `@AssistedFactory` and `@SubContainerFactory` |
| Runtime circular-dependency detection | Compile-time and build-time cycle rejection |

## Migration Steps

1. Pick one composition root, such as the app entry point or one feature, and
   declare a `@DIContainer` for it. Values that Factory read from outside the
   container, such as a base URL or a launch configuration, become `@Input`
   members.
2. Move each registration into a `@Provide` member. Choose the scope from the
   concept map, and name every sibling dependency as a factory-closure
   parameter so InnoDI can record the edge.
3. Replace `@Injected` and `Container.shared` lookups inside types with
   initializer parameters. Only the composition root reads members from the
   container.
4. Move test and preview registrations to the generated `Overrides` builder.
   A test builds its own container, so tests no longer need to reset a shared
   container between cases.
5. Attach `InnoDIDAGValidationPlugin` to every target that declares a
   container, and run `swift run InnoDI-DependencyGraph --root . --validate-dag`
   in CI.

During the transition, Factory and InnoDI can coexist. Resolve a value from
Factory at the composition root and pass it into the InnoDI container as an
`@Input`; remove the Factory registration once no type reads it.

## Example

The comments name the Factory registration each member replaces.

<!-- innodi:compile -->
```swift
import InnoDI

protocol WeatherAPI: Sendable {
    func temperature(for city: String) -> Int
}

struct LiveWeatherAPI: WeatherAPI {
    let baseURL: String
    func temperature(for city: String) -> Int { city.count }
}

struct StubWeatherAPI: WeatherAPI {
    func temperature(for city: String) -> Int { 21 }
}

final class ForecastViewModel {
    private let api: any WeatherAPI

    init(api: any WeatherAPI) {
        self.api = api
    }

    func headline(for city: String) -> String {
        "\(city): \(api.temperature(for: city))°"
    }
}

@DIContainer
struct AppContainer {
    @Input var baseURL: String

    // Factory: `self { LiveWeatherAPI(baseURL: ...) }.singleton`
    @Provide(.shared, factory: { (baseURL: String) in
        LiveWeatherAPI(baseURL: baseURL)
    })
    var weatherAPI: any WeatherAPI

    // Factory: `self { ForecastViewModel(api: self.weatherAPI()) }`
    @Provide(.transient, factory: { (weatherAPI: any WeatherAPI) in
        ForecastViewModel(api: weatherAPI)
    })
    var forecastViewModel: ForecastViewModel
}

let live = AppContainer(baseURL: "https://api.example.com")
print(live.forecastViewModel.headline(for: "Seoul"))

// Factory: `Container.shared.weatherAPI.register { StubWeatherAPI() }`
let preview = AppContainer(baseURL: "https://api.example.com") { overrides in
    overrides.weatherAPI = StubWeatherAPI()
}
print(preview.forecastViewModel.headline(for: "Seoul"))
```

## See Also

- <doc:MigratingFromSwinject>
- <doc:Provide>
- <doc:PolicyBoundaries>
