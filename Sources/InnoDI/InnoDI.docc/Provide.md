# Provide

`@Provide` declares a container member and its construction strategy.

## Declaration

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

## Construction Modes

- `factory`: synchronous construction expression or closure
- `asyncFactory`: asynchronous construction closure
- `Type.self` plus `with:`: explicit autowiring

## Rules

- `factory` and `asyncFactory` are mutually exclusive.
- `.input` does not allow `factory` or `asyncFactory`.
- `.shared` and `.transient` require a construction strategy.
- `asyncFactory` must be an `async` closure.
- Concrete `.shared` and `.transient` storage requires `concrete: true`.
- Name resolution for factory parameters and `with:` dependencies is strict by
  member name.

## See Also

- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
- <doc:Validation>
