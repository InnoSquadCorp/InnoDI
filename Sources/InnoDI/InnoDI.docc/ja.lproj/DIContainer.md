# DIContainer

`@DIContainer` は、サポート対象の実質的に非ジェネリックな struct を
InnoDI コンテナとして表し、コンテナ API を合成します。

`@DIContainer` がサポートするのは、ファイルスコープまたは nominal type 内に
ネストされた、実質的に非ジェネリックな `struct` 宣言だけです。宣言自体にも、
それを囲む宣言にも、ジェネリックパラメータや `where` 句を指定できません。
`class`、`actor`、`enum`、`protocol`、直接アノテーションした `extension`、
extension 内にネストされた struct は拒否されます。関数、クロージャ、
アクセサ、`switch` case など、実行可能またはローカルなコードスコープ内の
宣言も拒否されます。この境界は `@DIComponent` を併用した宣言にも適用されます。
ランタイムまたは型固有の状態は、protocol dependency または
`@Provide(.input)` の背後に移してください。

現在の Swift compiler は、computed-property body 内の型に attached macro を
展開するとき、accessor ancestry を macro context に含めません。この edge case
は build-validation plugin と dependency-graph CLI が source 全体を scan して
拒否します。container を宣言するすべての target に plugin を接続してください。

## Declaration

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Generated Surface

- primary `init(...)`
- ネスト `Overrides`
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- 4 つの `withOverrides`

ユーザー定義のネスト `Overrides` がない限り、サポート対象の各コンテナが
overrides scaffolding を生成します。

## Parameters

- `root`: グラフ描画エントリだけを制御
- `validateDAG`: global DAG validation と local cycle / closure-`with:` を制御
- `mainActor`: 依存関係 accessor、生成されるすべての initializer、
  `Overrides`、convenience initializer・`withOverrides`・child override・
  component mount で使う `applyOverrides` 関数型、4 つの `withOverrides`
  operation closure、feature-root helper を `@MainActor` に隔離します。
  `@DIComponent` を併用すると、生成される `<Container>Dependencies` protocol
  と `init(dependencies:_:)` も同じ隔離を受け、component は専用の
  `_InnoDIMainActorComponentMountable` protocol に準拠します。このオプションを
  使わない通常の component は `_InnoDIComponentMountable` を引き続き使用します。
  non-`Sendable` な生成値は `@MainActor` caller を使うか、同じ
  `MainActor.run` block 内で生成して利用し、main actor に保持してください。
  direct `await` は隔離された処理が `Sendable` な結果を返す場合に適しており、
  container 自体を actor 外へ運ぶためのものではありません。
