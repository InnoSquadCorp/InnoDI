# Policy Boundaries

InnoDI 通过显式边界来保持校验的确定性。

## 自定义 `init` 检测

- 宏校验只会拒绝 annotated type body 中的自定义 `init`。
- 必需的 `InnoDIDAGValidationPlugin` full-source preflight 会拒绝同文件和跨文件
  匹配 extension 中的 `init`，包括 `#if` 分支内的声明。
- 如果未应用 build-validation plugin，则无法保证在所有 extension 中执行该
  禁止规则，因为 attached macro 无法可靠地检查 sibling extension。

## Generated qualifier 与 bridge 边界

- 为每个声明 InnoDI container 或 standalone `@DIEnvironmentBridge` 的 target 附加
  `InnoDIDAGValidationPlugin`。
- target-scoped full-source pass 会拒绝 attached macro 无法检查的 enclosing
  declaration、matching extension 与同一 target 其他 source 中的 generated
  qualifier shadow，以及已导入 dependency target 中可见的 `public` / `package`
  qualifier shadow。
- 它也会拒绝直接标注 extension 或声明在 standalone local scope 中的
  `@DIEnvironmentBridge`。请把 bridge target 移到 file 或 nominal scope。
- 对于 class bridge 或嵌套在 class 中的 generated site，第一个 inherited type
  必须能通过 source-visible declaration 和 typealias 解析。这个 pass 是保守的
  syntactic index，而不是 Swift 的 semantic type checker，因此仅存在于 SDK 或
  binary、无法解析或解析结果有歧义的第一个 inherited type 会以
  `generated-qualifier.inheritance-unverifiable` fail closed。
- source-visible superclass chain 会接受 qualifier shadow 检查。Bridge 生成会拒绝
  继承的 type member `Swift` 和 `SwiftUI`，但继承的 `InnoDISwiftUI` 是安全的。
  直接声明或 enclosing scope 中的 `InnoDISwiftUI` 仍是保留名称。

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
- 使用 component 角色的 `@DIContainerRole` 时，生成的依赖协议、`init(dependencies:_:)` 和 override
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

## 声明类型决定存储形态

- 推荐 protocol-first 的依赖设计。
- 声明的 property type 是唯一依据：具体 nominal type 使用具体存储，
  `any Protocol` 使用 existential 存储。
- 存储形态不由 attribute flag 或 macro heuristic 选择。
