# Provide

`@Provide` はコンテナメンバーと生成戦略を宣言します。

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

- `factory` と `asyncFactory` は同時に使えません
- `.input` は `factory` / `asyncFactory` を許可しません
- `.shared` と `.transient` は生成戦略が必要です
- `asyncFactory` は `async` closure でなければなりません
- concrete `.shared` / `.transient` には `concrete: true` が必要です
