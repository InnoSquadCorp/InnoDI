# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

面向 Swift 的宏驱动依赖注入框架，提供编译期与构建期校验、依赖图工具、
层级校验以及 SwiftUI 辅助能力。

## 最小可用示例

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String
    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## 为什么选择 InnoDI

InnoDI 适合希望让 DI wiring 保持显式、可审查，并尽可能提前发现错误的团队。

- `@DIContainer` 和 `@Provide` 从受支持的实际非泛型 Swift struct 生成容器 API。
- 宏校验会在展开阶段捕获局部错误。
- build validation 与 graph CLI 会发现跨文件、跨模块以及全局依赖图问题。
- `InnoDISwiftUI` 可以减少根边界处重复的 environment wiring。

InnoDI 不是运行时状态机。运行时状态应放在你的应用层或 `InnoFlow`、
`InnoRouter`、`InnoNetwork` 这类配套框架中。
InnoDI 有意不提供 `@Injected` property wrapper 或 dynamic registration API。
它选择的取舍是显式生成 initializer、可审查的 wiring，以及更早的校验。

## 何时选择 InnoDI

当依赖 wiring 需要在 code review 中清晰可见、在 runtime 之前完成校验，并能
作为 graph artifact 被检查时，选择 InnoDI。

| 优先目标 | 可选方案 | 原因 |
| --- | --- | --- |
| app dependency graph 的 compile/build-time validation | InnoDI、[SafeDI](https://github.com/dfed/SafeDI) 或 [Needle](https://github.com/uber/needle) | InnoDI 保留 macro-expanded Swift container surface，并提供 macro diagnostics、build-support checks 和 DAG CLI。 |
| runtime registration、late binding 或 plugin-like composition | [Swinject](https://github.com/Swinject/Swinject) 或 [Factory](https://github.com/hmlongco/Factory) | runtime container 更适合动态替换注册。InnoDI 刻意优先选择显式 initializer 和早期校验。 |
| SwiftUI previews 与 scoped test overrides | [Factory](https://github.com/hmlongco/Factory)、[swift-dependencies](https://github.com/pointfreeco/swift-dependencies) 或 InnoDI | 当这些 override 应建立在 validated app container 与 generated SwiftUI root helpers 之上时，InnoDI 更合适。 |
| hierarchical feature ownership 与 graph visibility | InnoDI、[Needle](https://github.com/uber/needle) 或 [SafeDI](https://github.com/dfed/SafeDI) | InnoDI 使用 `@SubContainer` 建模 parent-owned child containers，并在 graph CLI 中渲染 ownership edges。 |
| 既有 app 的最低导入成本 | [Factory](https://github.com/hmlongco/Factory)、[swift-dependencies](https://github.com/pointfreeco/swift-dependencies) 或渐进式 InnoDI adoption | InnoDI 需要定义 container 并接受 macro/build validation；当你需要可审查 wiring、generated overrides 和 graph checks 时，这个成本才值得。 |

实践中 InnoDI 也可以与 runtime tools 共存：用 InnoDI 校验 application graph，
在 feature logic 内使用 `swift-dependencies` 或小型 factories 处理局部
runtime values。

实战中较稳的分层是：把*构造*交给 InnoDI，把*调用粒度的临时 override*交给
`swift-dependencies`。composition root 解析 `DependencyKey`（例如
`@Dependency(\.date)`）后，把结果作为 `.input` 槽传入 container；测试用
`withDependencies { $0.date = .constant(...) } operation:` 只替换一棵调用树，
无需重新构造 container，也无需重新校验 graph。container 级 `Overrides`
builder 仍是替换全 app 范围依赖（如假 `APIClient`）的正确工具；只有当
override 仅应在单次 operation 内生效时，才取出 `swift-dependencies`。

## 要求

- Swift tools version `6.2`
- 平台：
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### 构建期 validator 的文件系统要求

构建插件会在 Swift Package Manager scratch 目录下使用分层 POSIX lock
串行化 live DAG validation：

1. `open(O_CREAT | O_EXCL | O_RDWR)` 创建唯一的 lock file。
2. `flock(LOCK_EX | LOCK_NB)` 在 descriptor 上添加 advisory exclusive lock。

InnoDI 会自动检测 lock directory 背后的文件系统。APFS、HFS+、ext4、
btrfs、xfs、tmpfs 等本地文件系统受支持。NFS mount、SMB/CIFS、WebDAV 和
FUSE 类文件系统默认会被拒绝，因为在 lock atomicity 不可靠时，并发构建可能
损坏共享 validation cache。

如果构建系统必须把 derived data 放在 shared volume 上，请把 SPM 的
`--scratch-path` 或 Xcode derived-data 位置指向本地目录：

```sh
swift build --scratch-path /tmp/innodi-cache
```

插件不会在 package root 的 `.build/innodi-dag-validation` 下创建 lock/cache
state；移动 scratch path 也会移动 validation state。

运维人员可以用 `INNODI_ALLOW_UNSAFE_LOCK=1` 绕过 unsafe-filesystem
fail-fast，但 InnoDI 仍会输出可审计的警告，风险仍由该 build environment
承担。诊断、恢复步骤和完整文件系统表见
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md)。

构建时验证器为快速迭代或受限环境提供两种 opt-out 逃生门：
`@DIContainer(validateDAG: false)` 按容器粒度生效，
`INNODI_DISABLE_BUILD_VALIDATION=1` 则使整个构建插件短路。每个 PR 都会运行
`Tools/report-validate-dag-escape-hatches.sh`，将所有使用这些逃生门的站点
列入工作流的 step summary，因此即使没有额外的 CI 门禁，逃生门的蔓延也保持
可见。生产 CI 必须让两者都保持 unset。

## 隐私

InnoDI 在两个运行时产品 `InnoDI` 和 `InnoDISwiftUI` 中附带 Apple Privacy
Manifest（`PrivacyInfo.xcprivacy`）。该清单声明无用户追踪、无追踪域名、无收集
的数据类型、无 Required Reason API 使用。构建时工具（InnoDIBuildSupport、
dependency-graph CLI、宏插件）不会嵌入到用户应用中，因此不会影响该清单。如果
将 InnoDI 嵌入到 iOS、watchOS、tvOS 或 visionOS 应用中，SwiftPM 会自动捆绑
该清单，并使其出现在应用的汇总隐私报告中。

## 安装

在 `Package.swift` 中加入：

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.3.0")
]
```

然后把需要的 product 加到 target：

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

只有需要 SwiftUI helper 时才添加 `InnoDISwiftUI`：

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

把 build-time DAG validator 插件加到每个声明 InnoDI container 的 target：

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

如果团队已经确认 source-tool 编译是主要采用成本，配套的
`InnoDIValidationTools` package 提供可选的 prebuilt macOS validation
plugin。只挂载上面的 source plugin 或 prebuilt plugin 之一，不能同时挂载；
unsupported hosts 和 local package development 应继续使用 source plugin。

## 快速开始

<!-- innodi:compile -->
```swift
import Foundation
import InnoDI

protocol APIClientProtocol {
    func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    func fetch() async throws -> Data { Data() }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
```

当名称或构造逻辑无法直接匹配 `Type.self` 加 `with:` 时，请使用 factory closure。

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## 建议阅读顺序

1. [Overview](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/PolicyBoundaries.md)
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

## 核心 API

### `@DIContainer`

`@DIContainer` 会合成：

1. 主 `init(...)`
2. 嵌套 `Overrides` 类型
3. `init(<inputs...>, _ applyOverrides: ...)` 便利初始化器
4. 四个 `withOverrides` 重载：`sync`、`throws`、`async`、`async throws`

除非用户已经声明了嵌套 `Overrides` 类型，否则每个受支持的容器都会生成
overrides scaffolding。

`@DIContainer` 仅支持文件作用域或名义类型内嵌套的实际非泛型 `struct` 声明。
声明本身及其任何外层声明都不能包含泛型参数或 `where` 子句。`class`、
`actor`、`enum`、`protocol`、直接标注的 `extension` 以及嵌套在 extension
中的 struct 都会被拒绝。任何可执行或局部代码作用域内的声明也会被拒绝，
包括函数、闭包、访问器和 `switch` case。
与 `@DIComponent` 叠加使用时同样受此边界限制。请把运行时状态或特定类型的
状态放到协议依赖或 `@Provide(.input)` 后面。

当前 Swift 编译器在为 computed-property body 内的类型展开 attached macro
时，不会把访问器祖先信息放进 macro context。build-validation plugin 和
dependency-graph CLI 会扫描完整 source tree，并拒绝这个边界情况。请为每个
声明容器的 target 挂载该 plugin。

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| 参数 | 默认值 | 含义 |
|---|---|---|
| `root` | `false` | 只影响图渲染入口。如果存在 root，Mermaid、DOT、ASCII 输出会裁剪为从 root 可达的节点与边。 |
| `validateDAG` | `true` | 开启全局 DAG 校验，以及宏的本地 cycle 与 closure/`with:` graph-derived 校验。设为 `false` 只跳过这部分；`factory:` 和 initializer 的 raw-expression 引用仍会在编译期诊断，结构性校验也仍然执行。 |
| `mainActor` | `false` | 给生成的容器 API 加上 `@MainActor` 隔离，适合 UI 根容器。 |

### `@Provide` 与作用域

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

| Scope | 含义 | 构造规则 |
|---|---|---|
| `.input` | 在初始化容器时由外部提供 | 不允许 `factory` 或 `asyncFactory` |
| `.shared` | 每个容器实例创建一次并复用 | 需要 `factory`、`asyncFactory`，或 `Type.self` 加 `with:` |
| `.transient` | 每次访问都重新创建 | 需要 `factory`、`asyncFactory`，或 `Type.self` 加 `with:` |

## 校验模型

InnoDI 分层校验：

1. Macro validation
2. Build validation
3. Global DAG validation

`validateDAG: false` 是刻意收窄的 opt-out。它只跳过全局 DAG 校验和宏的
本地 cycle / closure-`with:` graph-derived 校验，不会关闭结构性校验，也不会
屏蔽 raw-expression 引用的编译期诊断。

## Overrides Builder

生成的 `Overrides` builder 允许测试只覆盖自己关心的成员。

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

也可以把 override 限定到单次 operation：

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

只有 `.input` 的容器也会生成空 builder。若子容器只有 input，`<name>Overrides`
closure 依然可以编译，并作为 no-op 运行。

## `Lazy<T>` 与 `Provider<T>`

- `Lazy<T>` 用于把依赖边变成 soft edge，从而跳出 cycle detection。
- `Provider<T>` 用于每次调用时重新进入 `.transient` 依赖。

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
}, concrete: true)
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
}, concrete: true)
var logger: RequestLogger
```

这两个 wrapper 都刻意保持为 non-`Sendable`。

## 嵌套容器与层级

`@SubContainer` 用来建模父容器拥有的子容器：

```swift
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

关键规则：

- `scope:` 必填
- 只有父容器有 0 个或 1 个 `@Provide` 候选时，才会使用按名称的隐式 wiring。
  父容器有多个候选时必须显式添加 wiring，不要依赖生成的 Swift initializer
  错误。
- `with:` 转发同名的显式子集或顺序。它必须是宏可以读取的 key path
  字面量数组；不支持运行时变量或计算得到的数组元素。
- `with: []` 是显式的空子集，将调用 `Child()`。
- `bindings:` 将子容器 input label remap 到不同的父成员名。
- `with:`、`bindings:` 两种 wiring form 只能选择一种。
- 父容器的 `Overrides` 同时拥有完整替换槽 (`feature`) 和子容器 override
  closure (`featureOverrides`)。

跨模块 ownership 使用：

- `@DIComponent`
- `@DIHierarchyRoot`

## SwiftUI Helper

`InnoDISwiftUI` 提供：

- `.innodi(container)`
- `@DIEnvironmentBridge`
- `@DIFeatureRoot`

## CLI 与发布表面

```bash
swift run InnoDI-DependencyGraph --root .
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

发布说明与升级说明统一放在 [RELEASING.md](RELEASING.md)。

## 示例

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
