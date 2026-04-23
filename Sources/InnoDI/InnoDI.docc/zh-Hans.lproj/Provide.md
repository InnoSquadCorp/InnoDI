# Provide

`@Provide` 声明容器成员及其构造策略。

## 声明

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

## 规则

- `factory` 与 `asyncFactory` 互斥
- `.input` 不允许 `factory` 或 `asyncFactory`
- `.shared` 与 `.transient` 需要构造策略
- `asyncFactory` 必须是 `async` closure
- concrete `.shared` / `.transient` 需要 `concrete: true`
