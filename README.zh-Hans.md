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
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
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

- Swift tools version `6.2`（CI 验证：Swift 6.2 与 6.3）
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

把 build-time DAG validator 插件加到每个声明 InnoDI container 或 standalone
`@DIEnvironmentBridge` 的 target。target-scoped full-source pass 会拒绝 attached
macro 无法看到的 enclosing declaration 与同一 target 中的 generated qualifier
shadow，以及已导入 dependency target 中可见的 `public` / `package` qualifier
shadow，并在 Swift 编译前拒绝 bridge 的 direct-extension attachment 和 standalone
local target：

当 generated site 是 class 或 nested 在 class 内时，可能表示 superclass 的第一个
inherited type 必须能通过 source-visible declaration 与 typealias 解析。仅存在于
SDK、仅存在于 binary、无法解析或有歧义的第一个 inherited type 会以
`generated-qualifier.inheritance-unverifiable` fail closed。请把 generated site
移到 struct / enum 或 source-visible adapter，或者让 target-scoped source snapshot
可以看到 superclass chain。该 preflight 是保守的 syntactic index，不能替代
Swift type checker。

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

`InnoDIValidationTools` 目前是尚未发布的配套 package scaffold。仓库中已提交的
artifact 是会有意失败的 fail-safe placeholder，并不是可用的 prebuilt validator。
在 public release 发布并验证真实 artifact 之前，consumer 不得依赖该 package。
正式发布后，只挂载上面的 source plugin 或 prebuilt plugin 之一，不能同时挂载；
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

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
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

每个容器都会生成完整的 overrides scaffolding，即使没有受管理成员。InnoDI 5.0
不支持用户声明的嵌套 `Overrides` 类型，并会发出
`container.overrides-name-conflict`；请重命名该声明，让宏拥有可挂载的
override ABI。

宏还会为生成的父容器挂载代码生成保留的 compiler-support alias
`_InnoDIMountOverrides = Overrides`。不要直接声明或引用这个下划线名称。

容器中的每个存储型实例成员都必须使用 `@Provide` 或 `@SubContainer`；计算属性和
静态属性仍可使用。这样生成的初始化器会拥有全部状态，避免 memberwise
initializer ABI 漂移。

`@DIContainer` 仅支持文件作用域或名义类型内嵌套的实际非泛型 `struct` 声明。
声明本身及其任何外层声明都不能包含泛型参数或 `where` 子句。`class`、
`actor`、`enum`、`protocol`、直接标注的 `extension` 以及嵌套在 extension
中的 struct 都会被拒绝。任何可执行或局部代码作用域内的声明也会被拒绝，
包括函数、闭包、访问器和 `switch` case。
与 `@DIComponent` 叠加使用时同样受此边界限制。请把运行时状态或特定类型的
状态放到协议依赖或 `@Provide(.input)` 后面。

显式声明为 `private` 的容器也会被拒绝，因为同级容器无法访问其生成的挂载
接口。文件内挂载请使用 `fileprivate`，或在 private namespace 内嵌套使用
default access 的容器。

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
| `validateDAG` | `true` | 开启全局 DAG 校验以及宏的本地 graph-derived 校验。设为 `false` 会跳过全局 DAG 和本地 cycle 校验，但声明校验与显式 sibling edge 的效果兼容性校验仍会执行。 |
| `mainActor` | `false` | 为依赖访问器、所有生成的初始化器、`Overrides`、convenience initializer、`withOverrides`、子容器 override 与 component mounting 所使用的 `applyOverrides` 函数类型、四个 `withOverrides` 重载的操作闭包以及 feature-root helper 应用 `@MainActor` 隔离。与 `@DIComponent` 搭配时，生成的 `<Container>Dependencies` 协议和 `init(dependencies:_:)` 也会被隔离，并改为遵循专用协议 `_InnoDIMainActorComponentMountable`。未使用该选项的普通组件继续遵循 `_InnoDIComponentMountable`。主执行器之外的使用者需要显式 hop。推荐用于 UI 根容器。 |

在 5.0 中，generic component mounting helper 必须区分这两个 marker protocol。
普通组件继续使用 `_InnoDIComponentMountable`；对于 `mainActor: true` 组件，
请增加一个使用 `_InnoDIMainActorComponentMountable` constraint 并接收
`@MainActor` override closure 的 `@MainActor` overload。

非 `Sendable` 的 container/component 值应保留在主执行器内：使用
`@MainActor` caller，或在同一个 `MainActor.run` block 中完成构造和使用。只有当
隔离操作返回 `Sendable` 结果时，direct `await` 才合适，例如 `withOverrides`
operation result；它不会让 container 本身可以安全地带到执行器之外。

### `@Provide` 与作用域

InnoDI 5.0 只允许把 `@Provide` 标注在同一个受支持的 `@DIContainer` struct
中的直接、普通、存储型实例 `var` 上。`let`、computed/observed property、
`lazy`、`weak`、`unowned`、`static`/`class`、独立以及间接嵌套用法都会被拒绝。
生成的 provider accessor 由 InnoDI 所有；不要手动附加
`_InnoDIProvideAccessor`。

Provider 声明的 attribute 与 access control 也采用封闭契约。Property wrapper、
conditional 或 unknown attribute、`private(set)` 等 setter access modifier，以及
custom global-actor attribute 都会被拒绝。除 `@Provide` 外，不允许任何
source-written property-level attribute，其中也包括 `@MainActor`。请使用
`@DIContainer(mainActor: true)` 请求 actor 隔离。InnoDI 在 provider declaration
和 accessor 上生成的 isolation attribute 属于内部 compiler support。把完整的
`@Provide` member declaration 放在 `#if` 内也会
触发 `provide.conditional-declaration-unsupported`。请让声明保持无条件，并在
factory 或注入实现内部进行分支。

每个 property 只能附加一个 `@Provide`；重复 attribute 会以
`provide.duplicate-attribute` 拒绝。direct provider property 与 root factory
closure dependency parameter 各自都必须使用唯一的 effective name；duplicate
identity 会在生成 lookup 或 storage code 前被拒绝。这两类 declaration 都必须使用
unescaped identifier，5.0 会拒绝 backtick-escaped property 和 factory-parameter
name。`@SubContainer` property name 也必须 unescaped，因为生成的 child storage、
override 与 root-helper identity 都由它派生。

生成的 storage / support declaration 会保留 `_storage_`、`_override_`、
`_innoDI` 与 `_InnoDI` 前缀，direct declaration 的精确名称 `InnoDI` 也被保留。
`Swift`、`_Concurrency` 以及 SwiftUI bridge anchor 则在 attached macro 可见的
type namespace 中保留。完整的 5.0 matrix 请参阅
[Migration Guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md)。target-scoped
full-source pass 会拒绝 attached macro 看不到、但会遮蔽 generated qualifier 的
enclosing scope / same-target declaration，以及 imported dependency target 中可见的
`public` / `package` declaration。
对于 class bridge 或 enclosing class，该 scan 也会沿 source-visible superclass
chain 检查。继承的 type member `Swift` 与 `SwiftUI` 会被拒绝；继承的
`InnoDISwiftUI` member 则是安全的。direct 或 lexical scope 中可见的
`InnoDISwiftUI` declaration 仍然保留。由于这是保守的 syntactic index，仅存在于
SDK、仅存在于 binary、无法解析或有歧义的第一个 inherited type 不会被假设为没有
shadow，而会以 `generated-qualifier.inheritance-unverifiable` fail closed。

显式 property type 不能使用 opaque `some Protocol` 或 implicitly unwrapped
optional `T!`，请分别迁移到
`any Protocol`，或显式的 `T` / `T?`。如果刻意伪造 compiler-support accessor
并与另一个 property wrapper 组合，除了 InnoDI misuse diagnostic 外，Swift
自身也可能发出 structural diagnostic。

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    escaping: Bool = false
)
```

| Scope | 含义 | 构造规则 |
|---|---|---|
| `.input` | 在初始化容器时由外部提供 | 不声明 `factory:`、`asyncFactory:`、`Type.self`、property initializer 或 `with:` |
| `.shared` | 每个容器实例创建一次并复用 | 在 `factory:`、`asyncFactory:`、`Type.self`、property initializer 中恰好声明一个 |
| `.transient` | 每次访问都重新创建 | 在 `factory:`、`asyncFactory:`、`Type.self`、property initializer 中恰好声明一个 |

- 对 `.shared` / `.transient`，`factory:`、`asyncFactory:`、`Type.self` 和
  property initializer 这四种构造源互斥。
- `.input` 会拒绝所有构造源和 `with:`。
- 生成的 `.input` initializer 参数是声明类型 `T` 的 eager value；Swift 会像往常
  一样在调用 initializer 前求值 `try` / `await` 参数表达式。直接写出的
  non-optional function type 会被自动识别并生成 escaping 参数。如果
  non-optional function type 隐藏在 typealias 后，请使用
  `@Provide(.input, escaping: true)`。`escaping:` 必须是 literal Bool，且只在
  `.input` 有效。明显的 nonfunction / optional-function 形状会被拒绝；若保守接受的
  identifier/member alias 实际并不解析为 non-optional function，Swift 可能再发出
  自身的 diagnostic。
- `asyncFactory` 支持 `.shared` 和 `.transient`，且必须是 `async` closure。
- 声明的 property type 决定存储形态：具体 nominal type 使用具体存储，
  `any Protocol` 使用 existential 存储。
- `with:` 只能与 `Type.self` 构造一起使用。Literal 数组的每个元素必须精确采用
  canonical direct-member 写法 `\Self.member`，例如 `with: [\Self.config]`；
  `with: []` 也有效。具名 container、module-qualified 或 typealias root，以及
  nested component、optional chaining、subscript、计算得到的数组元素都会被拒绝。
  所有引用的 provider 都必须使用同步构造。

Sibling DI edge 只来自以下封闭语法：

- 根 `factory:` 或 `asyncFactory:` closure literal 的每个具名参数声明一条
  edge。嵌套 closure 和任意 identifier 不会增加 edge。
- `Type.self` 构造从 literal canonical `\Self.member` key-path 数组声明 edge，
  并且只能指向同步 provider。
- 非 closure 的 `factory:` 表达式和 property initializer 是不透明的
  zero-edge 构造源，不能引用 sibling container member。DI wiring 应改为根
  closure 参数；若不需要 DI edge，请使用 qualified global/static 构造符号。

Factory 效果必须显式声明，不会从依赖关系中推断。异步 consumer 应使用
`asyncFactory:`；消费可能抛错的异步 provider 时，必须将 closure 显式声明为
`async throws`。即使使用 `validateDAG: false`，每条显式 edge 仍会校验效果
兼容性。

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | 允许 | 允许 | 允许 |
| `async` | 拒绝 | 允许 | 允许 |
| `async throws` | 拒绝 | 拒绝 | 允许 |

`Lazy<T>` 和 `Provider<T>` 是同步 deferred wrapper，会拒绝异步 target。

## 校验模型

InnoDI 分层校验：

1. Macro validation
2. Build validation
3. Global DAG validation

`validateDAG: false` 是刻意收窄的 opt-out。它只跳过全局 DAG 以及本地 cycle
等 graph-derived 校验，不会关闭声明校验，也不会跳过根 closure 或 `with:`
产生的显式 sibling edge 的效果兼容性校验。

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
})
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
})
var logger: RequestLogger
```

这两个 wrapper 都刻意保持为 non-`Sendable`。它们也保持同步，不能以
`asyncFactory` member 为 target。

## 嵌套容器与层级

`@SubContainer` 用来建模父容器拥有的子容器：

```swift
@SubContainer(
    scope: .shared,
    with: [\.config, \.apiClient],
    featureRoot: FeatureRootScene.self
)
var feature: FeatureContainer
```

关键规则：

- `scope:` 必填
- 请在受支持的 parent `@DIContainer` 中、`#if` 之外的直接、普通、存储型实例
  `var` 上只声明一个 `@SubContainer`。不支持 wrapper、storage / accessor
  modifier、unknown attribute，或手动附加
  `InnoDI._InnoDISubContainerAccessor`。
- 只有父容器有 0 个或 1 个 `@Provide` 候选时，才会使用按名称的隐式 wiring。
  父容器有多个候选时必须显式添加 wiring，不要依赖生成的 Swift initializer
  错误。
- `with:` 转发同名的显式子集或顺序。它必须是宏可以读取的 key path
  字面量数组；不支持运行时变量或计算得到的数组元素。
- `with: []` 是显式的空子集，将调用 `Child()`。
- `bindings:` 将子容器 input label remap 到不同的父成员名。
- `featureRoot:` / `featureRoots:` 会在 parent container 上生成 SwiftUI root
  helper，无需在同一个 property 上叠加另一个 peer macro。
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
- `@SubContainer(..., featureRoot:)` 和 `featureRoots:` 会为子容器生成默认或
  命名的 feature-root helper。
- InnoDI 5.0 移除了已弃用的兼容宏 `@DIFeatureRoot`。请改用
  `@SubContainer` 的 feature-root 参数。

## CLI 与发布表面

```bash
swift run InnoDI-DependencyGraph --root . --root-pruning all
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

检查 consumer target 中由宏生成的 Swift 代码：

```bash
Tools/dump-macro-expansions.sh \
  --package-path /path/to/ConsumerPackage \
  --target App
```

请从 InnoDI checkout 运行脚本，并让 `--package-path` 指向 consumer。脚本使用
隔离的 scratch build，默认把合并结果写入 consumer 的
`.build/innodi/macro-expansions.swift`，并拒绝写入 `Sources/` 或 `Tests/`。
consumer 的常规 build cache 不会被修改。只检查一个声明时，Xcode 的
**Expand Macro** 仍然最快。

发布说明与升级说明统一放在 [RELEASING.md](RELEASING.md)。

## 示例

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
