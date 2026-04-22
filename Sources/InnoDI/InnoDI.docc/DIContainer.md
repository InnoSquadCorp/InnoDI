# DIContainer

`@DIContainer` marks a type as a dependency container and generates an initializer from declared members.
User-defined `init` declarations are unsupported inside the annotated type and any extension.

## Declaration

```swift
@DIContainer(
    root: Bool = false,
    validateDAG: Bool = true,
    mainActor: Bool = false
)
```

## Parameters

- `root`: Marks the container as a graph-rendering entry. If any containers declare `root: true`, render output is limited to the union of nodes and edges reachable from those roots.
- `validateDAG`: Enables global DAG validation plus the macro's graph-derived local checks for this container. When set to `false`, global DAG validation and the macro's local cycle plus closure/`with:` diagnostics are skipped, but raw-expression `factory:` / initializer references and structural diagnostics still remain active.
- `mainActor`: Applies `@MainActor` isolation to generated APIs. Prefer this for SwiftUI or other UI-root containers under strict concurrency.

## Example

```swift
@DIContainer(mainActor: true)
struct AppContainer {
    @Provide(.input)
    var config: AppConfig
}
```

## Strict Concurrency

- ``Lazy`` and ``Provider`` are intentionally non-`Sendable` deferred handles.
  Keep them on the container's original isolation domain instead of moving
  them across actors.
- `mainActor: true` is the recommended isolation boundary for UI-facing
  containers.
- InnoDI still hardens transient sub-container builders and init-time
  late-binding storage for strict concurrency, but a container can only adopt
  `Sendable` when its remaining stored members and override closures also
  satisfy Swift's rules.

## See Also

- ``DIContainer(root:validateDAG:mainActor:)``
- <doc:Provide>
