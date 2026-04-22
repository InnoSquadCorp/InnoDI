# Module-Wide Init Detection

`@DIContainer` 在宏层和构建层都限制自定义 `init`。

## Macro Layer

- annotated type body 中禁止自定义 `init`
- 同文件、同类型路径的 extension 中也禁止

## Build Layer

- 同一规则扩展到 cross-file extension
- 模糊或不支持的情况保持在规则之外
