# Provide

`@Provide` deklariert ein Container-Mitglied und seine Erzeugungsstrategie.

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

- `factory` und `asyncFactory` schliessen sich gegenseitig aus.
- `.input` erlaubt weder `factory` noch `asyncFactory`.
- `.shared` und `.transient` brauchen eine Konstruktionsstrategie.
- `asyncFactory` muss eine `async`-Closure sein.
- Konkrete `.shared`- und `.transient`-Typen brauchen `concrete: true`.
