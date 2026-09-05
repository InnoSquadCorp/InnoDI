# Provide

`@Provide` はコンテナメンバーと生成戦略を宣言します。

InnoDI 6.0 では、`@Provide` は同じ supported `@DIContainer` struct の direct
かつ plain な stored instance `var` にのみ指定できます。`let`、
computed/observed property、`lazy`、`weak`、`unowned`、`static`/`class`、
standalone、間接的な nested usage は拒否されます。生成 accessor は InnoDI が
所有するため、`_InnoDIProvideAccessor` を手動で付与しないでください。

Property wrapper、conditional/unknown attribute、`private(set)` などの setter
access modifier、custom global-actor attribute も拒否されます。`@Provide` 以外の
source-written property-level attribute は許可されず、`@MainActor` も含まれます。
actor isolation は `@DIContainerRole(role: ContainerRole.local, mainActor: true)` で指定してください。provider
declaration と accessor に InnoDI が生成する isolation attribute は internal
compiler support です。完全な `@Provide` member declaration を `#if` 内に置くと
`provide.conditional-declaration-unsupported` になります。宣言を条件の外に
置き、factory または注入する実装の内部で分岐してください。

各 property に指定できる `@Provide` は正確に 1 つです。重複 attribute は
`provide.duplicate-attribute` で拒否されます。明示的な property type に opaque
`some Protocol` または implicitly unwrapped optional `T!` は使用できません。
それぞれ `any Protocol`、明示的な `T` / `T?` に移行してください。
compiler-support accessor と別の property wrapper を意図的に偽装して併用した
場合、InnoDI misuse diagnostic に加えて Swift structural diagnostic が発生する
ことがあります。

## Declaration

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    initialization: DIInitialization = .eager,
    factory: Any? = nil,
    asyncFactory: Any? = nil
)
```

## Input value と escaping function

生成される `@Input` initializer parameter は宣言型 `T` の eager value です。
Swift は initializer call の前に各 argument を評価するため、
`try makeValue()` と `await makeValue()` はそのまま有効な argument expression
です。直接記述された non-optional function type は自動検出され、escaping
parameter として生成されます。typealias の背後にある場合は
`@Input(escaping: true)` を宣言してください。

`escaping:` は literal Bool で、`@Input` でのみ有効です。明らかな nonfunction
または optional-function shape は安定した InnoDI diagnostic で拒否されます。
attached macro は任意の alias を解決できないため identifier/member type を
保守的に許可し、alias が実際には non-optional function でない場合は Swift
自身の diagnostic が追加されることがあります。

## Rules

- `factory:`、`asyncFactory:`、`Type.self`、property initializer は相互排他的な
  construction source です
- `@Input` はすべての construction source と `with:` を拒否します
- `.shared` と `.transient` は正確に 1 つの construction source が必要です
- `with:` は `Type.self` と同期 provider でのみ利用できます
- `asyncFactory` は `.shared` と `.transient` で利用でき、`async` closure
  でなければなりません
- 宣言した property type が storage shape を決定します。具象の nominal type は
  具象 storage、`any Protocol` は existential storage になります

## Sibling edge contract

- root `factory:` / `asyncFactory:` closure literal の named parameter だけが
  edge を宣言します。nested closure や任意 identifier は edge を追加しません。
- `Type.self` は literal `with:` array から edge を宣言します。各 key path は
  `with: [\Self.config]` のように canonical direct-member 表記 `\Self.member` を
  正確に使う必要があります。`with: []` も有効です。named container、
  module-qualified、typealias root、nested component、optional chaining、
  subscript、computed element は拒否されます。すべての target は同期
  construction を使用する必要があります。
- closure ではない factory と property initializer は opaque な zero-edge
  source で、sibling member を参照できません。root closure parameter または
  qualified global/static symbol を使用してください。

## Provider effect の互換性

Factory effect は明示的に宣言し、依存関係から推論しません。非同期 consumer
には `asyncFactory:` を使い、throwing な非同期 provider を消費する場合は
closure に `async throws` を明記してください。この互換性は
`validateDAG: false` でも検証されます。

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | 許可 | 許可 | 許可 |
| `async` | 拒否 | 許可 | 許可 |
| `async throws` | 拒否 | 拒否 | 許可 |

`Lazy<T>` と `Provider<T>` は同期 deferred wrapper のままです。どちらも
`asyncFactory:` で構築される target を拒否します。
