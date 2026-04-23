# DIContainer

`@DIContainer` は InnoDI コンテナを表し、コンテナ API を合成します。

## Declaration

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Generated Surface

- primary `init(...)`
- ネスト `Overrides`
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- 4 つの `withOverrides`

ユーザー定義のネスト `Overrides` がない限り、すべてのコンテナが
overrides scaffolding を生成します。

## Parameters

- `root`: グラフ描画エントリだけを制御
- `validateDAG`: global DAG validation と local cycle / closure-`with:` を制御
- `mainActor`: 生成 API に `@MainActor` を適用
