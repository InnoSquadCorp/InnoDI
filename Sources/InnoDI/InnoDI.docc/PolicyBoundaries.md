# Policy Boundaries

InnoDI keeps validation deterministic by choosing a few explicit boundaries.

## Custom `init` Detection

- Macro validation rejects custom `init` declarations in the annotated type.
- The required `InnoDIDAGValidationPlugin` full-source preflight rejects custom
  `init` declarations in matching same-file and cross-file extensions,
  including declarations inside `#if` branches.
- Without the build-validation plugin, the extension-wide custom `init`
  prohibition is not guaranteed because attached macros cannot reliably inspect
  sibling extensions.

## Matching Strategy

- `InnoDIMacros`, `InnoDICore`, and `InnoDI-DependencyGraph` share and
  guarantee the same lightweight nominal-path model and aligned parser/graph
  semantics.
- Nested paths such as `Outer.Container` are supported.
- Generic argument extensions and constrained `where` extensions are excluded.
- Unsupported or ambiguous cases stay outside the semantic rule instead of
  producing speculative matches.

## Declaration Order

- `.input` members are always available.
- sync `.shared` members can reference inputs and earlier sync shared members.
- async `.shared` members can reference inputs, sync shared members, and
  earlier async shared members.
- `.transient` members may reference any container member, but names still
  resolve strictly.

## Provider Effects

- A synchronous provider can be consumed by sync, `async`, and `async throws`
  factories.
- An `async` provider requires an `async` or `async throws` consumer.
- An `async throws` provider requires an `async throws` consumer.
- Effects are never inferred from dependencies. Consumers opt in explicitly
  with `asyncFactory:` and, when needed, an `async throws` closure.
- `Lazy<T>` and `Provider<T>` are synchronous deferred wrappers and reject
  async targets.

## Isolation and Sendability

- Containers keep their generated storage inside the container value. InnoDI
  does not install dependencies into a global registry.
- `mainActor: true` isolates dependency accessors, every generated initializer,
  `Overrides`, the `applyOverrides` function types used by convenience
  initializers, `withOverrides`, child overrides, and component mounting, all
  four `withOverrides` operation closures, and generated feature-root helpers.
  It is the preferred shape for UI-root containers.
- When paired with `@DIComponent`, the generated dependency protocol and
  `init(dependencies:_:)` are `@MainActor`, including the override-application
  closure type, and the component conforms to the dedicated
  `_InnoDIMainActorComponentMountable` protocol. Ordinary components continue
  to use the nonisolated `_InnoDIComponentMountable` protocol. In 5.0, generic
  mounting helpers must provide separate constraints and closure types for
  these two markers.
- Keep generated container/component values and non-`Sendable` dependencies on
  the main actor. Prefer an `@MainActor` caller or a `MainActor.run` block that
  both constructs and consumes those values. A direct `await` is appropriate
  when the isolated operation returns a `Sendable` result, such as a
  `withOverrides` operation result; it does not make a non-`Sendable` container
  safe to carry back off actor.
- `Lazy<T>` and `Provider<T>` wrappers are not a cross-actor transport
  mechanism. Treat them as staying inside the container's isolation domain
  unless `T` and the surrounding call path are already safe to move.
- Non-`Sendable` dependencies should be passed through explicit container
  boundaries and isolated by the app layer, not hidden behind global lookup.

## DAG Opt-Outs

- `validateDAG: false` disables graph-derived cycle and unresolved-reference
  checks for that container.
- Structural validation still runs. Unsupported custom `init` declarations,
  invalid `@SubContainer` bindings, malformed deferred wrappers, and other
  local macro rules are still diagnosed.
- Use the opt-out only for deliberate integration boundaries such as legacy
  modules, temporary migration steps, or containers whose real lifetime is
  validated by another system.

## Deferred Wrapper Limits

- `Lazy<T>` and `Provider<T>` defer container-member access after init-time
  wiring, so those edges are rendered but excluded from hard cycle detection.
- The deferral is only effective when the factory receives the wrapper and
  stores or forwards it. If a factory immediately calls the wrapper while constructing
  the dependency, the dependency is effectively eager again. InnoDI diagnoses
  direct `lazy()` / `provider()` calls and their direct `callAsFunction()` /
  `resolver()` spellings inside `.shared` construction.
- Indirect eager calls through helper functions are not type-checked by InnoDI;
  review those factories manually when breaking cycles with deferred wrappers.

<!-- innodi:compile -->
```swift
import InnoDI

struct Config {}
struct Service { init(config: Config) {} }
struct Request { init(config: Config) {} }
struct Consumer {
    let service: Lazy<Service>
    let requests: Provider<Request>
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: Config

    @Provide(.shared, factory: { (config: Config) in
        Service(config: config)
    })
    var service: Service

    @Provide(.transient, factory: { (config: Config) in
        Request(config: config)
    })
    var request: Request

    @Provide(.shared, factory: { (service: Lazy<Service>, request: Provider<Request>) in
        Consumer(service: service, requests: request)
    })
    var consumer: Consumer
}

let container = AppContainer(config: Config())
_ = container.consumer
```

<!-- innodi:compile -->
```swift
import InnoDI

struct Config {}
struct FeatureService { init(config: Config) {} }

@DIContainer
struct FeatureContainer {
    @Provide(.input)
    var featureConfig: Config

    @Provide(.shared, factory: { (featureConfig: Config) in
        FeatureService(config: featureConfig)
    })
    var service: FeatureService
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var config: Config

    @SubContainer(
        scope: .shared,
        bindings: [(child: \FeatureContainer.featureConfig, parent: \AppContainer.config)]
    )
    var feature: FeatureContainer
}

let container = AppContainer(config: Config())
_ = container.feature
```

## Declared Storage Shape

- Protocol-first dependency design is preferred.
- The declared property type is the source of truth: a concrete nominal type
  uses concrete storage, while `any Protocol` uses existential storage.
- Storage shape is not selected by an attribute flag or macro heuristic.

## Runtime Lookup Tradeoffs

- InnoDI intentionally has no `@Injected` property wrapper.
- InnoDI intentionally has no dynamic registration API.
- Use runtime DI tools when late registration or plugin-style composition is
  the primary need. Use InnoDI when generated initializers, explicit overrides,
  and deterministic validation are the primary need.

## See Also

- <doc:Validation>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
