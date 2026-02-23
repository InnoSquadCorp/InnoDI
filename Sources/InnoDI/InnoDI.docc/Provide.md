# Provide

`@Provide` declares a container member and its construction strategy.

## Declaration

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any? = nil,
    with: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

## Construction Modes

- `factory`: Synchronous construction expression or closure.
- `asyncFactory`: Asynchronous closure for async construction.
- `Type.self` + `with:`: Auto-wiring using explicit key path dependencies.

## Rules

- `factory` and `asyncFactory` are mutually exclusive.
- `.input` cannot declare `factory` or `asyncFactory`.
- `asyncFactory` must be an `async` closure.
- Concrete value types/protocol-erased rules still follow `concrete` validation.

## Example

```swift
@Provide(.shared, asyncFactory: { (config: AppConfig) async throws in
    try await APIClient.make(config: config)
})
var apiClient: any APIClientProtocol
```

## See Also

- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
- <doc:Validation>
