# Provide

`@Provide` объявляет член контейнера и стратегию его построения.

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

## Rules

- `factory` и `asyncFactory` взаимоисключают друг друга
- `.input` не допускает `factory` и `asyncFactory`
- `.shared` и `.transient` требуют стратегию построения
- `asyncFactory` должен быть `async` closure
- concrete `.shared` / `.transient` требуют `concrete: true`
