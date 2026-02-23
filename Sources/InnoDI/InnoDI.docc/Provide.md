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
- `.shared` and `.transient` must provide a construction strategy:
  use `factory`, `asyncFactory`, or explicit `Type.self` + `with:` auto-wiring.
- `.input` cannot declare `factory` or `asyncFactory`, so it is mutually exclusive with
  those construction APIs.
- `asyncFactory` must be an `async` closure.
- `concrete` validation is applied consistently for both concrete types and
  protocol-erased declarations.

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
