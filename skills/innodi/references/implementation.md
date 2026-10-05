# Implementing a 7.0.0 consumer

## Package and target setup

Use the [complete Package.swift](../assets/consumer/Package.swift) as a small, exact-version example. The consumer target links `InnoDI`, optionally `InnoDISwiftUI`, and attaches `.plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")`. Test/preview support can link `InnoDITesting` where needed. Attaching the plugin to the package but not the declaring target is insufficient; standalone `@DIEnvironmentBridge` targets also need it.

The tools-version is 6.2, but the example was tested with Swift 6.4 / Xcode 27. Do not promise every Swift 6.2 toolchain works with SwiftSyntax 604. See [compatibility.md](compatibility.md).

## Declaration decisions

| Need | 7.0.0 shape and constraint |
|---|---|
| Simple container | `@DIContainer` on a struct; exactly one container macro |
| Explicit role or MainActor shorthand | `@DIContainerRole(role: ContainerRole.local, mainActor: true)`; `component` and `root` roles are available for hierarchy |
| Borrowed value | `@Input var config: Config`; supply at initialization, no factory/initializer |
| Shared or per-access construction | `@Provide(.shared, ...)` caches; `.transient` constructs on each read |
| Typed synchronous constructor | `@Provide(.shared, Client.self, with: [\Self.config])`; literal type and key paths, synchronous dependencies |
| Closure construction | `factory: { (config: Config) in ... }`; named root parameters establish dependency edges |
| Deferred synchronous shared value | `initialization: .onDemand`; first access constructs, copies share the cache, separate initializations are independent |
| Async construction | `asyncFactory:`; choose eager/on-demand and ownership using [async-lifecycle.md](async-lifecycle.md) |

Providers are direct stored `var` declarations. Choose one construction source: `factory:`, `asyncFactory:`, typed `Type.self` wiring, or a supported property initializer. Do not stack construction sources, property wrappers, or provider-level actor isolation. Conditional container-member declarations are not supported. Avoid effectively generic containers.

Default shared initialization follows declaration order. Opt in to `ContainerInitializationOrder.dependency` only when dependency ordering is intended; this can change observable factory effects. Express MainActor on the container, either explicitly or through the role macro. Target default MainActor settings do not replace that declaration.

Use typed, synchronous, nonthrowing `services.prewarm(.label)` for selected synchronous on-demand providers. `prewarm()` with no selections does nothing. It is not 6.x's throwing key-path API and does not prepare asynchronous providers.

## Overrides and tests

The [AppServices example](../assets/consumer/Sources/InnoDISkillExample/Services.swift) and [tests](../assets/consumer/Tests/InnoDISkillExampleTests/ConsumerTests.swift) cover typed construction, factory bypass, selective prewarm and copies:

- Ordinary nonoptional values can use the generated builder's assignment, such as `$0.client = fake`.
- Use `$0.set(\.label, to: nil)` for an explicit optional nil. Use `$0.useDefault(\.label)` to restore normal construction. A builder's unset slot and an explicit nil payload differ.
- A dependency override skips that factory and its dependency resolution; independently declared eager providers may still run. Do not infer that one override eliminates all side effects.
- Inject manual fakes first when that meets the test. `@GenerateMock` is opt-in and its generated shape remains experimental; inspect the exact [AutoMock guide](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/AutoMock.md) before using generated members.

## Hierarchy and SwiftUI boundaries

For `@SubContainer` parent wiring use `\Self.member`; named roots and nested parent paths are not interchangeable shorthand. Match child inputs to the selected same-name or `bindings:` form. Async parent members cannot be injected as synchronous child inputs. Read the exact [macro signatures](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.swift) before generating child, assisted, collection, or feature-root declarations; these shapes are outside the bundled sample.

Files using SwiftUI or generated SwiftUI helper names must explicitly `import SwiftUI` alongside `import InnoDISwiftUI`. Hosted feature-root helpers require `FeatureRoot(RootView.self, hosted: true)`. Unhosted helpers remain direct construction. `DIContainerHostOwner` uses Observation, not Combine's `ObservableObject`; use `@State` for a view-owned host owner and read `phase` from an observing context. The sample verifies explicit SwiftUI imports and value injection, not host teardown or device behavior.

Sources: exact [Provide contract](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/Provide.md), [integration guide](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/IntegrationGuide.md), and [migration guide](https://github.com/InnoSquadCorp/InnoDI/blob/4783eee7f674f99a337768c107b7a5f640810c2a/Sources/InnoDI/InnoDI.docc/MigrationGuide.md). Adapted patterns retain the [upstream notice](../THIRD_PARTY_NOTICES.md).
