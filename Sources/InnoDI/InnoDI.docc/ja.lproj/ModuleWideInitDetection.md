# Module-Wide Init Detection

`@DIContainer` はマクロ層とビルド層の両方で custom `init` を制限します。

## Macro Layer

- annotated type body の custom `init` を拒否
- 同じ型パスを指す same-file extension の `init` も拒否

## Build Layer

- 同じルールを cross-file extension まで拡張
- 曖昧または未対応のケースは deterministic rule の外に置く
