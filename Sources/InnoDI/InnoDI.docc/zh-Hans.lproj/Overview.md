# ``InnoDI``

为 Swift 提供分层校验的宏驱动依赖注入。

## Overview

InnoDI 通过 `@DIContainer` 与 `@Provide` 把普通 Swift 类型转换为 DI
容器。它强调显式 wiring、确定性校验与图工具，而不是运行时可变容器。

4.0.0 的稳定基线包括：

- 宏生成的容器 API
- 编译期与构建期校验
- 全局依赖图渲染与 DAG 校验
- `Lazy<T>` 与 `Provider<T>`
- `@SubContainer`、`@DIComponent`、`@DIHierarchyRoot`
- `InnoDISwiftUI` 中的 SwiftUI helper

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
