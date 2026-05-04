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

4.1.0 在该基线之上加入 release hardening：

- validation coordinator lock 的 unsafe filesystem fail-fast
- 在受支持文件系统上同时使用 `O_CREAT | O_EXCL` 和 `flock` 的分层 lock
- 用 build-time diagnostic 取代宏合成的 `fatalError` accessor
- PR/release gate 同时强制 strict concurrency 和 macro-source `fatalError` allow-list
- 针对未叠加 peer macro 的 `withNames:` 用法提供 `@SubContainer` Fix-it 指引

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
