# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

面向 Swift 的宏驱动依赖注入框架，提供编译期与构建期校验、依赖图工具、
层级校验以及 SwiftUI 辅助能力。

## 最小可用示例

```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String
    @Provide(.shared, APIClient.self, with: [\.baseURL], concrete: true)
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## 为什么选择 InnoDI

InnoDI 适合希望让 DI wiring 保持显式、可审查，并尽可能提前发现错误的团队。

- `@DIContainer` 和 `@Provide` 从普通 Swift 类型生成容器 API。
- 宏校验会在展开阶段捕获局部错误。
- build validation 与 graph CLI 会发现跨文件、跨模块以及全局依赖图问题。
- `InnoDISwiftUI` 可以减少根边界处重复的 environment wiring。

InnoDI 不是运行时状态机。运行时状态应放在你的应用层或 `InnoFlow`、
`InnoRouter`、`InnoNetwork` 这类配套框架中。
InnoDI 有意不提供 `@Injected` property wrapper 或 dynamic registration API。
它选择的取舍是显式生成 initializer、可审查的 wiring，以及更早的校验。

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

运维人员可以用 `INNODI_ALLOW_UNSAFE_LOCK=1` 绕过 unsafe-filesystem
fail-fast，但 InnoDI 仍会输出可审计的警告，风险仍由该 build environment
承担。诊断、恢复步骤和完整文件系统表见
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md)。

## 安装

在 `Package.swift` 中加入：

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.1.0")
]
```

然后把需要的 product 加到 target：

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

如果不用 SwiftUI helper，只需导入 `InnoDI`。

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

## 快速开始

```swift
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

    @Provide(.shared, APIClient.self, with: [\.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
let client = container.apiClient
```

当名称或构造逻辑无法直接匹配 `Type.self` 加 `with:` 时，请使用 factory closure。

## 建议阅读顺序

1. [Overview](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/PolicyBoundaries.md)
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/zh-Hans.lproj/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

## 核心 API

### `@DIContainer`

`@DIContainer` 会合成：

1. 主 `init(...)`
2. 嵌套 `Overrides` 类型
3. `init(<inputs...>, _ applyOverrides: ...)` 便利初始化器
4. 四个 `withOverrides` 重载：`sync`、`throws`、`async`、`async throws`

除非用户已经声明了嵌套 `Overrides` 类型，否则所有容器都会生成 overrides
scaffolding。

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| 参数 | 默认值 | 含义 |
|---|---|---|
| `root` | `false` | 只影响图渲染入口。如果存在 root，Mermaid、DOT、ASCII 输出会裁剪为从 root 可达的节点与边。 |
| `validateDAG` | `true` | 开启全局 DAG 校验，以及宏的本地 cycle 与 closure/`with:` graph-derived 校验。设为 `false` 只跳过这部分；`factory:` 和 initializer 的 raw-expression 引用仍会在编译期诊断，结构性校验也仍然执行。 |
| `mainActor` | `false` | 给生成的容器 API 加上 `@MainActor` 隔离，适合 UI 根容器。 |

### `@Provide` 与作用域

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

只有 `.input` 的容器也会生成空 builder。若子容器只有 input，`<name>Overrides`
closure 依然可以编译，并作为 no-op 运行。

## `Lazy<T>` 与 `Provider<T>`

- `Lazy<T>` 用于把依赖边变成 soft edge，从而跳出 cycle detection。
- `Provider<T>` 用于每次调用时重新进入 `.transient` 依赖。

这两个 wrapper 都刻意保持为 non-`Sendable`。

## 嵌套容器与层级

`@SubContainer` 用来建模父容器拥有的子容器：

```swift
@SubContainer(scope: .shared, withNames: ["config", "apiClient"])
var feature: FeatureContainer
```

关键规则：

- `scope:` 必填
- 只有父容器有 0 个或 1 个 `@Provide` 候选时，才会使用按名称的隐式 wiring。
  父容器有多个候选时必须显式添加 wiring，不要依赖生成的 Swift initializer
  错误。
- `with:` 或 `withNames:` 转发同名的显式子集或顺序。两种形式都必须是宏可
  以读取的字面量数组；不支持运行时变量或计算得到的数组元素。
- `with: []` 或 `withNames: []` 是显式的空子集，将调用 `Child()`。
- `bindings:` 将子容器 input label remap 到不同的父成员名。
- `with:`、`withNames:`、`bindings:` 三种 wiring form 只能选择一种。
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
