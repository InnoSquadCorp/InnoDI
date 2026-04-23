# Validation

InnoDI は複数の層で依存定義を検証します。

## Macro Validation

マクロ検証は次を確認します。

- scope ルール
- factory の欠落
- 宣言順
- ローカル cycle
- 厳密な名前解決
- 許可されない user-defined `init`

`validateDAG: false` は構造検証を無効化しません。

## Build Validation

coordinated build pipeline は以下を追加します。

1. cross-file `init` 検証
2. semantic reference check
3. hierarchy validation
4. DAG validation
5. metrics / summary artifact 出力
