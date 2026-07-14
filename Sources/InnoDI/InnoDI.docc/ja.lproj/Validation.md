# Validation

InnoDI は複数の層で依存定義を検証します。

## Macro Validation

マクロ検証は次を確認します。

- scope ルール
- `@Provide` の direct/plain/stored instance `var` 配置
- factory の欠落
- 宣言順
- ローカル cycle
- 厳密な名前解決
- 明示的 sibling edge の effect compatibility
- 許可されない user-defined `init`

明示的 sibling edge は root `factory:`/`asyncFactory:` closure literal の named
parameter、または `Type.self` と literal `with:` key path だけから生成されます。
非 closure factory と property initializer は opaque な zero-edge source で、
sibling member を参照できません。

`validateDAG: false` は宣言検証や effect compatibility を無効化しません。
global DAG、local cycle、その他の graph-derived check だけを省略します。

## Build Validation

coordinated build pipeline は以下を追加します。

1. cross-file `init` 検証
2. semantic reference check
3. hierarchy validation
4. DAG validation
5. metrics / summary artifact 出力
