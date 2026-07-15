# Module-Wide Init Detection

`@DIContainer` 在宏层和构建层都限制自定义 `init`。

## Macro Layer

宏校验只会拒绝 annotated type body 中的自定义 `init`。attached macro 无法可靠地
检查同一源文件中的 sibling extension。

## 必需的 Build Layer

每个声明容器的 target 都必须接入 `InnoDIDAGValidationPlugin`。它的 full-source
preflight 会拒绝同文件和跨文件匹配 extension 中的 `init`，包括 `#if` 分支内的
声明。

如果未应用 build-validation plugin，则无法保证在所有 extension 中禁止自定义
`init`。模糊或不支持的情况仍保持在确定性规则之外。
