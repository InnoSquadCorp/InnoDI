# DIContainer

`@DIContainer` marks a type as a dependency container and generates an initializer from declared members.
User-defined `init` declarations are unsupported inside the annotated type and its same-file extensions.

## Declaration

```swift
@DIContainer(
    validate: Bool = true,
    root: Bool = false,
    validateDAG: Bool = true,
    mainActor: Bool = false
)
```

## Parameters

- `validate`: Reserved compatibility flag. Missing factories and invalid scope usage remain compile-time errors.
- `root`: Marks the container as a root node for dependency graph rendering.
- `validateDAG`: Enables local/global dependency cycle validation for this container.
- `mainActor`: Applies `@MainActor` isolation to generated APIs.

## Example

```swift
@DIContainer(mainActor: true)
struct AppContainer {
    @Provide(.input)
    var config: AppConfig
}
```

## See Also

- ``DIContainer(validate:root:validateDAG:mainActor:)``
- <doc:Provide>
