# Module-Wide Init Detection

`@DIContainer` はマクロ層とビルド層の両方で custom `init` を制限します。

## Macro Layer

マクロ検証が custom `init` を拒否できるのは annotated type body 内だけです。
attached macro は、同じソースファイルにある sibling extension を確実には参照
できません。

## 必須の Build Layer

コンテナを宣言するすべての target に `InnoDIDAGValidationPlugin` を追加して
ください。full-source preflight は、same-file と cross-file の両方の一致する
extension にある `init` を、`#if` branch 内の宣言も含めて拒否します。

build-validation plugin を適用しない場合、すべての extension に対する custom
`init` の禁止は保証されません。曖昧または未対応のケースは deterministic rule
の外に置かれます。
