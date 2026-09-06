# Provide

`@Provide` 声明容器成员及其构造策略。

InnoDI 6.0 只允许把 `@Provide` 标注在同一个受支持的 `@DIContainer` struct
中的直接、普通、存储型实例 `var` 上。`let`、computed/observed property、
`lazy`、`weak`、`unowned`、`static`/`class`、独立与间接嵌套用法都会被拒绝。
生成的 accessor 归 InnoDI 所有；不要手动附加 `_InnoDIProvideAccessor`。

Property wrapper、conditional/unknown attribute、`private(set)` 等 setter
access modifier，以及 custom global-actor attribute 也会被拒绝。除 `@Provide`
外，不允许任何 source-written property-level attribute，其中也包括 `@MainActor`。
请使用 `@DIContainerRole(role: ContainerRole.local, mainActor: true)` 请求 actor 隔离。InnoDI 在 provider
declaration 和 accessor 上生成的 isolation attribute 属于内部 compiler support。
完整的 `@Provide` member declaration
位于 `#if` 内时会触发 `provide.conditional-declaration-unsupported`；请将声明放在
条件之外，并在 factory 或注入实现内部进行分支。

每个 property 只能附加一个 `@Provide`；重复 attribute 会以
`provide.duplicate-attribute` 拒绝。显式 property type 不能使用 opaque
`some Protocol` 或 implicitly unwrapped optional `T!`，请分别迁移到
`any Protocol`，或显式的 `T` / `T?`。如果刻意伪造 compiler-support accessor
并与另一个 property wrapper 组合，除了 InnoDI misuse diagnostic 外，Swift
自身也可能发出 structural diagnostic。

## 声明

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    effect: DIProviderEffect = .none,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

## Input 值与 escaping 函数

生成的 `@Input` initializer 参数是声明类型 `T` 的 eager value。Swift 会在调用
initializer 前求值每个参数，因此 `try makeValue()` 与 `await makeValue()` 仍是
有效的参数表达式。直接写出的 non-optional function type 会被自动识别并生成
escaping 参数；如果它隐藏在 typealias 后，请声明
`@Input(escaping: true)`。

`escaping:` 必须是 literal Bool，且只在 `@Input` 有效。明显的 nonfunction 或
optional-function 形状会以稳定的 InnoDI diagnostic 拒绝。由于 attached macro
无法解析任意 alias，identifier/member type 会被保守接受；若该 alias 实际并非
non-optional function type，Swift 可能追加自身的 diagnostic。

## 规则

- `factory:`、`asyncFactory:`、`Type.self` 与 property initializer 是互斥的
  construction source
- `@Input` 不允许任何 construction source 或 `with:`
- `.shared` 与 `.transient` 必须恰好声明一个 construction source
- `with:` 只能与 `Type.self` 和同步 provider 一起使用
- `asyncFactory` 支持 `.shared` 和 `.transient`，且必须是 `async` closure
- 声明的 property type 决定存储形态：具体 nominal type 使用具体存储，
  `any Protocol` 使用 existential 存储

## Sibling edge 契约

- 只有根 `factory:` / `asyncFactory:` closure literal 的具名参数会声明 edge。
  嵌套 closure 和任意 identifier 不会增加 edge。
- `Type.self` 从 literal `with:` 数组声明 edge。每个元素必须精确采用
  canonical direct-member 写法 `\Self.member`，例如 `with: [\Self.config]`；
  `with: []` 也有效。具名 container、module-qualified 或 typealias root，以及
  nested component、optional chaining、subscript、计算得到的元素都会被拒绝。
  所有 target 都必须使用同步构造。
- 非 closure factory 和 property initializer 是不透明的 zero-edge 构造源，
  不能引用 sibling member。请使用根 closure 参数或 qualified global/static
  构造符号。

## Provider 效果兼容性

Factory 效果必须显式声明，不会从依赖关系中推断。异步 consumer 应使用
`asyncFactory:`；消费可能抛错的异步 provider 时，必须将 closure 显式声明为
`async throws`。使用 `validateDAG: false` 时也会校验这种兼容性。

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | 允许 | 允许 | 允许 |
| `async` | 拒绝 | 允许 | 允许 |
| `async throws` | 拒绝 | 拒绝 | 允许 |

`Lazy<T>` 和 `Provider<T>` 仍是同步 deferred wrapper。两者都拒绝由
`asyncFactory:` 构造的 target。
