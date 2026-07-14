# Policy Boundaries

InnoDI は明示的な境界を置くことで検証を決定的に保ちます。

## Matching Strategy

- マクロ、Core、graph CLI は可能な限り同じ nominal-path モデルを共有
- `Outer.Container` のような nested path をサポート
- generic argument extension と `where` extension は除外
- 曖昧なケースは推測で一致させない

## Provider effect

- 同期 provider は sync、`async`、`async throws` factory から利用できます。
- `async` provider には `async` または `async throws` consumer が必要です。
- `async throws` provider には `async throws` consumer が必要です。
- Effect は依存関係から推論しません。Consumer が `asyncFactory:` と、必要なら
  `async throws` closure を明示します。
- `Lazy<T>` と `Provider<T>` は同期 deferred wrapper であり、非同期 target を
  拒否します。

## 隔離と Sendability

- コンテナは生成された storage をコンテナ値の内部に保持します。InnoDI は
  依存関係を global registry に登録しません。
- `mainActor: true` は依存関係 accessor、生成されるすべての initializer、
  `Overrides`、convenience initializer・`withOverrides`・child override・
  component mount で使う `applyOverrides` 関数型、4 つの `withOverrides`
  operation closure、生成される feature-root helper を隔離します。UI ルート
  コンテナ向けの構成です。
- `@DIComponent` を併用すると、生成される dependency protocol、
  `init(dependencies:_:)`、override 適用 closure 型は `@MainActor` に隔離され、
  component は専用の `_InnoDIMainActorComponentMountable` protocol に準拠します。
  通常の component は非隔離の `_InnoDIComponentMountable` を引き続き使用します。
  5.0 の generic mounting helper は、2 つの marker ごとに constraint と closure
  型を分けて提供する必要があります。
- 生成された container/component 値と non-`Sendable` な依存関係は main actor
  内に保持してください。`@MainActor` caller、または値の生成と利用を同じ
  `MainActor.run` block 内で行う形を推奨します。direct `await` は
  `withOverrides` operation result のように、隔離された処理が `Sendable` な
  結果を返す場合に適しています。non-`Sendable` container を actor 外へ安全に
  持ち出せるようにするものではありません。
- `Lazy<T>` と `Provider<T>` wrapper は actor 間の転送手段ではありません。
  `T` と周囲の呼び出し経路を安全に移動できる場合を除き、コンテナの隔離 domain
  内にとどまるものとして扱ってください。
- non-`Sendable` な依存関係は global lookup の背後に隠さず、明示的なコンテナ
  境界を通して渡し、アプリ層で隔離してください。
