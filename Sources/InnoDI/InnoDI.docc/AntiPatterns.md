# Anti-Patterns

Use InnoDI as a compile-time wiring boundary, not as a runtime state
container. These patterns usually make dependency graphs harder to review and
weaken the validation that InnoDI is designed to provide.

## Service-Locator Containers

Do not hide lookups behind a generic `resolve(_:)` method or pass the whole
container through feature code.

```swift
// Avoid
final class FeatureModel {
    let container: AppContainer

    func load() async throws {
        try await container.apiClient.fetch()
    }
}
```

Prefer exposing the dependency the feature actually needs:

```swift
struct FeatureModel {
    let apiClient: any APIClientProtocol
}
```

The container should build the graph at the root boundary; feature logic should
receive explicit values.

## Runtime State Inside Containers

Do not store UI state, navigation state, modal stores, or mutable view-model
state in a DI container. Containers are graph construction surfaces.

Keep runtime state in the app or companion framework layer. For example,
modal presentation state belongs in the flow/router layer, while InnoDI should
only provide services that the flow needs.

## Generated Storage Access

Never read or write generated storage such as `_storage_*`, `_override_*`, or
`_innoDI*` members directly. Those names are implementation details and are
reserved so the macro can evolve safely.

Use the public generated accessors, synthesized initializers, and
`withOverrides` APIs instead.

## Long-Lived Test Overrides

Avoid carrying override-heavy containers across unrelated tests. It is easy to
accidentally test the override graph rather than production wiring.

Prefer small per-test overrides:

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

Use `withOverrides` when the replacement should exist for one operation only.

## Companion Framework Boundary Mistakes

If a feature uses `ModalStore`, router stores, or flow stores, do not mutate
those stores from generated DI accessors or hide them inside the container.
InnoDI should construct the services and feature roots; the companion framework
should own runtime transitions and state mutation.

## See Also

- <doc:PolicyBoundaries>
- <doc:Validation>
- <doc:MigrationGuide>
