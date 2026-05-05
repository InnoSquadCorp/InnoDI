# Tutorial 5 — Nested containers with `@SubContainer`

Compose a parent and a child container so a feature gets its own scope
without losing access to shared inputs from the application root.

## Goal

A `FeatureContainer` that owns a `FeatureService` per parent instance,
wired through `@SubContainer` and the `with:` key-path form.

## Code

<!-- innodi:compile -->
```swift
import InnoDI

struct AppConfig {
    let baseURL: String
}

struct FeatureService {
    init(config: AppConfig) { self.config = config }
    let config: AppConfig
    func describe() -> String { "feature service for \(config.baseURL)" }
}

@DIContainer
struct FeatureContainer {
    @Provide(.input)
    var config: AppConfig

    @Provide(.shared, FeatureService.self, with: [\FeatureContainer.config], concrete: true)
    var service: FeatureService
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: AppConfig

    @SubContainer(scope: .shared, with: [\AppContainer.config])
    var feature: FeatureContainer
}

let container = AppContainer(config: AppConfig(baseURL: "https://example.com"))
print(container.feature.service.describe())
```

## What the macro adds

* `@SubContainer(scope: .shared, with: [\AppContainer.config])` tells the
  macro to construct one `FeatureContainer` per parent instance and to
  forward the parent's `config` member as the same-named child input.
* The parent's nested `Overrides` builder now exposes two slots for the
  child: `feature` (full replacement) and `featureOverrides`
  (forward-an-overrides-closure for the child's own builder). Both stay
  available even when the child has no overrideable members yet.
* Because the wiring uses `with:`, the parent and child member names line
  up. If the labels differ, switch to `bindings:`:
  `bindings: [(child: \FeatureContainer.config, parent: \AppContainer.environment)]`.

## When to choose `.shared` vs `.transient`

* `.shared`: the child is constructed once during parent initialization
  and reused on every read. Use for coordinator-like children whose
  internal `.shared` graph should remain stable.
* `.transient`: a fresh child is built per read. Use for per-screen or
  per-request scopes where the child is a wiring namespace, not a
  long-lived owner.

## Try it

* Override the child entirely from a test:
  `overrides.feature = FeatureContainer(config: testConfig)`.
* Forward an overrides block instead:
  `overrides.featureOverrides = { $0.service = MockFeatureService() }`.
* Stack the child with `@DIComponent` for cross-module ownership and
  re-read <doc:DIContainer> for the cross-module surface.

## Where to go next

- <doc:Validation>
- <doc:DAGValidation>
- <doc:MigrationGuide>
