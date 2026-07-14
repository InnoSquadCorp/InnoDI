# Policy Boundaries

InnoDI 通过显式边界来保持校验的确定性。

## Matching Strategy

- 宏、Core 与 graph CLI 尽量共享同一个 nominal-path 模型
- 支持 `Outer.Container` 这类嵌套路径
- 排除带泛型参数的 extension 与带 `where` 的 extension
- 模糊情况不会做推测性匹配

## Provider 效果

- 同步 provider 可由 sync、`async` 和 `async throws` factory 消费。
- `async` provider 要求 consumer 为 `async` 或 `async throws`。
- `async throws` provider 要求 consumer 为 `async throws`。
- 效果不会从依赖关系中推断。Consumer 必须显式使用 `asyncFactory:`，并在需要时
  声明 `async throws` closure。
- `Lazy<T>` 和 `Provider<T>` 是同步 deferred wrapper，会拒绝异步 target。

## 隔离与 Sendability

- 容器把生成的存储保留在容器值内部。InnoDI 不会把依赖放进全局注册表。
- `mainActor: true` 会隔离依赖访问器、所有生成的初始化器、`Overrides`、
  convenience initializer、`withOverrides`、子容器 override 与 component
  mounting 所使用的 `applyOverrides` 函数类型、四个 `withOverrides` 重载的操作
  闭包以及生成的 feature-root helper。这是 UI 根容器的推荐形式。
- 与 `@DIComponent` 搭配时，生成的依赖协议、`init(dependencies:_:)` 和 override
  closure 类型会被 `@MainActor` 隔离，component 会改为遵循专用协议
  `_InnoDIMainActorComponentMountable`。普通 component 继续遵循非隔离的
  `_InnoDIComponentMountable`。在 5.0 中，generic mounting helper 必须为这两个
  marker 分别提供 constraint 和 closure 类型。
- 生成的 container/component 值和非 `Sendable` 依赖应保留在主执行器内。优先
  使用 `@MainActor` caller，或在同一个 `MainActor.run` block 中完成这些值的构造
  与使用。只有当隔离操作返回 `Sendable` 结果时，direct `await` 才合适，例如
  `withOverrides` 的 operation result；它不会让非 `Sendable` container 可以安全地
  带回主执行器之外。
- `Lazy<T>` 和 `Provider<T>` wrapper 不是跨 actor 的传输机制。除非 `T` 和
  周边调用路径本身可以安全传输，否则应把它们视为留在容器的隔离域内。
- 非 `Sendable` 依赖应通过明确的容器边界传递，并由应用层隔离，而不是隐藏在
  全局 lookup 后面。
