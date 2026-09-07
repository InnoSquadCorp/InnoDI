# DIContainer

`@DIContainer` 用来把受支持的实际非泛型 struct 标记为 InnoDI 容器并合成
容器表面。

`@DIContainer` 仅支持文件作用域或名义类型内嵌套的实际非泛型 `struct` 声明。
声明本身及其任何外层声明都不能包含泛型参数或 `where` 子句。`class`、
`actor`、`enum`、`protocol`、直接标注的 `extension` 以及嵌套在 extension
中的 struct 都会被拒绝。任何可执行或局部代码作用域内的声明也会被拒绝，
包括函数、闭包、访问器和 `switch` case。
使用 component 角色的 `@DIContainerRole` 时同样受此边界限制。请把运行时状态或特定类型的
状态放到协议依赖或 `@Input` 后面。

显式声明为 `private` 的容器也会被拒绝，因为同级容器无法访问其生成的挂载
接口。文件内挂载请使用 `fileprivate`，或在 private namespace 内嵌套使用
default access 的容器。

当前 Swift 编译器在为 computed-property body 内的类型展开 attached macro
时，不会把访问器祖先信息放进 macro context。build-validation plugin 和
dependency-graph CLI 会扫描完整 source tree，并拒绝这个边界情况。请为每个
声明容器的 target 挂载该 plugin。

## 声明

```swift
@DIContainer(validateDAG: Bool = true)
@DIContainerRole(role: String, mainActor: Bool = false, validateDAG: Bool = true)
```

## 生成内容

- primary `init(...)`
- 嵌套 `Overrides`
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- 四个 `withOverrides` 重载

对于未使用 `mainActor: true` 的容器，生成的 `async` 与 `async throws`
`withOverrides` 方法及其 operation closure 类型采用
`nonisolated(nonsending)`。它们保留 caller 的 actor executor，因此任意非
`Sendable` 的 container 与 closure 值不会跨越 isolation boundary。同步重载
保持不变；使用 `mainActor: true` 时，所有 `withOverrides` 重载和 operation
closure 仍为 `@MainActor`。

每个容器都会生成完整的 overrides scaffolding，即使没有受管理成员。InnoDI 6.0
不支持用户声明的嵌套 `Overrides` 类型，并会发出
`container.overrides-name-conflict`；请重命名该声明，让宏拥有可挂载的
override ABI。

宏还会为生成的父容器挂载代码生成保留的 compiler-support alias
`_InnoDIMountOverrides = Overrides`。不要直接声明或引用这个下划线名称。

每个存储型实例成员都必须使用 `@Provide` 或 `@SubContainer`；计算属性和类型属性仍
可使用。这样合成初始化器会拥有全部存储状态，避免 memberwise initializer ABI
漂移。

每个 `@Provide` 都必须是此 struct 的直接、普通、存储型实例 `var`。
Accessor/observer、`let`、`lazy`、`weak`、`unowned`、`static`/`class`、独立或
间接嵌套的 provider 都会被拒绝；也不能手动附加生成 accessor。

Sibling edge 只来自根 `factory:`/`asyncFactory:` closure literal 的具名参数，
或 `Type.self` 与 literal `with:` key path。非 closure factory 和 property
initializer 是不透明的 zero-edge 构造源，不能引用 sibling member。即使使用
`validateDAG: false`，效果兼容性也必须满足。

## 参数

- `root`：只影响图渲染入口
- `validateDAG`：控制全局 DAG 与本地 graph-derived 校验；设为 `false` 也不会
  关闭声明校验和显式 sibling edge 的效果兼容性校验
- `mainActor`：为依赖访问器、所有生成的初始化器、`Overrides`、convenience
  initializer、`withOverrides`、子容器 override 与 component mounting 所使用的
  `applyOverrides` 函数类型、四个 `withOverrides` 重载的操作闭包以及
  feature-root helper 应用 `@MainActor` 隔离。使用 component 角色时，生成的
  `<Container>Dependencies` 协议和 `init(dependencies:_:)` 也会获得相同隔离，
  component 会改为遵循专用协议 `_InnoDIMainActorComponentMountable`。未使用该
  选项的普通 component 继续遵循 `_InnoDIComponentMountable`。对于非
  `Sendable` 的生成值，请使用 `@MainActor` caller，或在同一个
  `MainActor.run` block 中完成构造和使用，使其留在主执行器内。direct `await`
  适用于返回 `Sendable` 结果的隔离操作，而不是把 container 本身带到执行器之外。
