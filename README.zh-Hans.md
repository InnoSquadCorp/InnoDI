# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

<!-- innodi:guide version=7.0.1 -->
## 版本与适用范围

本页是 **InnoDI 7.0.1 的简体中文精简用户指南**，介绍基于宏的依赖注入、编译期与构建期验证、依赖图工具和 SwiftUI 集成。InnoDI 不提供动态注册 API，也不提供 `@Injected` 属性包装器。

完整说明以 [英文 README](README.md) 为准；另有 [韩文 README](README.ko.md) 和 [韩文 DocC](Sources/InnoDI/InnoDI.docc/ko.lproj/Overview.md)。下文的深入指南链接默认指向英文文档。本页更新并不表示已经提供完整的简体中文 DocC 翻译。需要核对发布时的内容，请查看 [7.0.1 标签下的文档](https://github.com/InnoSquadCorp/InnoDI/blob/7.0.1/README.md)。

<!-- innodi:section requirements -->
## 环境要求与兼容性

- Swift 6.2 或更高版本（包的 tools version 为 `6.2`）
- iOS 17+、macOS 14+、watchOS 10+、tvOS 17+、visionOS 1+
- **仅支持 Apple 平台**。CI 不在 Linux 上构建或测试，且 `InnoDITesting` 无条件导入 Apple 的 `os` 模块
- `swift-syntax` 精确锁定为 `604.0.0`。Mockable 0.6.4 要求 `509.0.0..<604.0.0`，因此二者无法在同一个 SwiftPM 依赖图中完成版本解析。请查看 [7.0.1 升级说明](CHANGELOG.md#701)
- 验证插件在 SwiftPM scratch 目录中保存锁和缓存，该目录必须位于 APFS 等本地文件系统上。默认拒绝 NFS、SMB、WebDAV 和 FUSE。[锁安全说明](Sources/InnoDI/InnoDI.docc/lock-safety.md)

<!-- innodi:section installation -->
## 安装

### 1. 添加包与所需产品

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "7.0.1")
]
```


核心产品为 `InnoDI`。使用 SwiftUI 辅助功能时添加 `InnoDISwiftUI`。仅在使用生成式 mock 或覆盖预设的测试、预览支持目标中添加 `InnoDITesting`。使用 `InnoDISwiftUI` 的文件必须显式写出 `import SwiftUI`，即使只有生成代码引用了 SwiftUI。

### 2. 配置必需的验证插件

在**每个**声明 InnoDI 容器或独立 `@DIEnvironmentBridge` 的目标上添加 `InnoDIDAGValidationPlugin`：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "InnoDI", package: "InnoDI")
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

插件是正确性保障的一部分，用于验证单个宏无法看到的跨文件初始化器、名称遮蔽和全局依赖图等问题。Xcode、Tuist 的设置与限制见 [Integration Guide](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md#build-plugin)。`validateDAG: false` 和 `INNODI_DISABLE_BUILD_VALIDATION=1` 是绕过验证的选项，并非正常安装步骤；生产 CI 不应禁用验证。[禁用验证的范围与限制](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)

<!-- innodi:section quickstart -->
## 最小示例

完成上述配置后，可用真实值和测试值构建同一个服务。以下代码与英文版的最小示例完全一致。

如果目标的默认隔离设置为 MainActor，请在容器上显式标注 `@MainActor` 或 `nonisolated`；宏无法推断这一构建设置。[隔离边界说明](Sources/InnoDI/InnoDI.docc/DIContainer.md#targets-with-default-mainactor-isolation)

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Input var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let live = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = APIClient(baseURL: "https://test.example.com")
}
precondition(live.apiClient.baseURL == "https://api.example.com")
precondition(test.apiClient.baseURL == "https://test.example.com")
```

<!-- innodi:section api -->
## API 选择指南

| 需求 | API 与注意事项 |
| --- | --- |
| 传入外部构建的值 | `@Input`：初始化时传入，不指定工厂或 `with:` |
| 共享一个服务 | `@Provide(.shared, ...)`：在同一容器中复用 |
| 每次访问都重新构建 | `@Provide(.transient, ...)`：不缓存结果 |
| 将同步服务推迟到首次访问时构建 | 为 `.shared` 指定 `initialization: .onDemand`；容器副本共享同一个逻辑缓存，分别初始化的容器相互独立 |
| 显式指定构造类型和依赖 | `Type.self` 与 `with: [\Self.member]`：只能引用直接的同步成员 |
| 自定义构建逻辑或执行异步构建 | `factory:` / `asyncFactory:`：通过最外层闭包的参数名声明同级依赖 |
| 延迟解析同步依赖 | `Lazy<T>` / `Provider<T>`：不能指向异步提供者，`Provider<T>` 只接受同步 transient 目标 |
| 构建子容器或带运行时参数的子容器 | `@SubContainer` / `@SubContainerFactory`：[容器层级](README.md#nested-containers-and-hierarchy) |
| 管理异步服务的准备、重试与关闭 | `@DIContainer(generateOwned: true)`：[显式所有权容器](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) |
| 在 SwiftUI 根边界传递依赖 | `InnoDISwiftUI` 与生成的辅助 API：[SwiftUI 集成](README.md#swiftui-helpers) |

容器必须采用受支持、实际不含泛型的 `struct` 声明。`@Provide` 只能直接标注该结构体内普通的存储实例 `var`。构建来源（`factory:`、`asyncFactory:`、`Type.self`、属性初始值）互斥。闭包依赖严格按名称解析，`async` / `throws` 不会从依赖自动推断。[声明与 effect 限制](Sources/InnoDI/InnoDI.docc/Provide.md)

<!-- innodi:section lifecycle -->
## 异步生命周期：就绪与关闭

- `makeOwned` 完成**不等于服务已就绪**。它允许 eager 异步提供者开始工作，但不会等待其结果全部就绪
- 使用 `prepare` 返回的报告时，必须检查 `report.isReady`。`requireReady` 会在未就绪时抛出错误，但不会关闭所有者。`withPrepared` 只在选定依赖子图就绪后运行操作，并在成功或失败返回前等待 `close()` 完成
- 选定子图就绪并不保证其他独立 eager 提供者正常。`retryAndRequireReady` 只执行一次显式重试，不是自动重试循环，也不是刷新操作
- 取消等待 `prepare` 的任务，不一定会取消提供者本身。需要显式调用 `await owner.close()`；离开作用域不会自动关闭
- `close()` 关闭生成的异步作用域，并拒绝后续异步读取。它不会等待忽略取消的工厂执行完毕，不会调用已返回服务的 `shutdown()`，不会使已返回的值失效，也不会关闭应用自行创建的任务。同步值、输入和普通子容器仍按借用值处理
- 未采用所有权 API 的普通 eager 异步 shared 提供者会在容器初始化时启动，容器不会取消该任务。`.onDemand` 异步 shared 则推迟到读取时启动，其访问器始终可能抛出错误。生成的 `closeAsyncProviders()` 的具体约定见 [异步 shared 生命周期](Sources/InnoDI/InnoDI.docc/Provide.md#asynchronous-shared-lifetime)

完整约定见 [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) 与 [Async Preparation](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md)。不要把 `close()` 当作应用级关闭完成的保证。

<!-- innodi:section testing -->
## 测试、覆盖与预览

最小示例通过 `Overrides` 构建器将真实服务替换成测试值。要将覆盖限定在一次操作中，可用 `withOverrides`；要用预设创建显式所有权容器，可用 `makeOwnedWithOverrides`。后者不会自动准备或关闭容器。异步值覆盖不执行工厂，而是直接创建 ready 状态的作用域，但仍会验证完整的已声明依赖图。

`@GenerateMock` 是**需要显式启用的实验性 API**，生成形式可能变化。`InnoDITesting` 的 stub 验证、调用记录、考虑代次的重置及类型化预设见 [Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md) 和 [测试支持 API](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)。预览配置见 [SwiftUI Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md)。

<!-- innodi:section diagnostics -->
## 诊断与迁移命令

在可运行这些工具的 InnoDI 仓库检出目录中执行以下命令，将 `/path/to/consumer` 替换为目标项目路径。先运行只读诊断和迁移检查：

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Doctor --root /path/to/consumer --json
swift run InnoDI-DependencyGraph --root /path/to/consumer --root-pruning all
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report --output migration-report.json
```

Doctor 默认的分析过程不会解析依赖、执行构建、修改源码、删除缓存或停止进程；不过用于启动工具的 `swift run` 本身可能先构建工具。对于无法解析的动态 Package.swift 或 Tuist 目标映射，Doctor 会明确标记检查不完整，不会将其视为完全正常。迁移报告不包含源码正文，退出码为 `0`（无需修改）、`1`（需要修改）、`2`（存在阻塞问题）。

审查结果后，再运行写入模式：

```bash
swift run InnoDI-Migrate --root /path/to/consumer --write
```

从 6.x 升级时，统一将父容器键路径写成 `\Self.member`，补充所需的 `import SwiftUI`，并将 macOS 最低版本提高到 14。类型化 prewarm 和所有权生命周期迁移不会自动完成。若替换前的文件保留在 `RECOVERY` 路径，请审查后再删除，并按使用方项目的常规配置重新构建、测试。[迁移指南](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#6x--70)

<!-- innodi:section documentation -->
## 按任务查找深入指南

| 任务 | 详细文档（英文） |
| --- | --- |
| 了解整体设计、创建第一个容器 | [Overview](Sources/InnoDI/InnoDI.docc/Overview.md)、[Hello](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md) |
| 逐步学习输入、连接、具体类型与子容器 | [Inputs](Sources/InnoDI/InnoDI.docc/Tutorial-02-Inputs.md)、[Wiring](Sources/InnoDI/InnoDI.docc/Tutorial-03-Wiring.md)、[Concrete](Sources/InnoDI/InnoDI.docc/Tutorial-04-Concrete.md)、[SubContainer](Sources/InnoDI/InnoDI.docc/Tutorial-05-SubContainer.md) |
| 了解生成 API、隔离与依赖顺序 | [DIContainer](Sources/InnoDI/InnoDI.docc/DIContainer.md)、[依赖顺序](Sources/InnoDI/InnoDI.docc/DIContainer.md#opt-in-dependency-ordering) |
| 配置作用域、工厂、effect 与 prewarm | [Provide](Sources/InnoDI/InnoDI.docc/Provide.md)、[Lazy / Provider](README.md#lazyt-and-providert) |
| 管理异步准备、重试与关闭 | [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md)、[Async Preparation](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md) |
| 组合层级、assisted factory 与集合 | [容器层级](README.md#nested-containers-and-hierarchy)、[集合组合](README.md#collection-composition) |
| 接入 SwiftUI、预览与测试 | [SwiftUI Helpers](README.md#swiftui-helpers)、[Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md)、[Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md)、[InnoDITesting](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md) |
| 配置插件、理解验证边界 | [Integration](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md)、[Validation](Sources/InnoDI/InnoDI.docc/Validation.md)、[DAG Validation](Sources/InnoDI/InnoDI.docc/DAGValidation.md)、[初始化器检测](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md) |
| 排查诊断、例外配置与锁故障 | [Diagnostics](Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md)、[Policy Boundaries](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)、[Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)、[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md)、[Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md) |
| 检查依赖图、CI 契约差异与运行时跟踪 | [CLI](README.md#cli-and-release-surface)、[Runtime Tracing](Sources/InnoDI/InnoDI.docc/RuntimeTracing.md)、[CI 运维策略](docs/automation-policy.md) |
| 升级或从其他 DI 工具迁移 | [Migration Guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md)、[从 Factory 迁移](Sources/InnoDI/InnoDI.docc/MigratingFromFactory.md)、[从 Swinject 迁移](Sources/InnoDI/InnoDI.docc/MigratingFromSwinject.md)、[CHANGELOG](CHANGELOG.md) |
| 查看示例与隐私说明 | [Examples](Examples)、[Privacy](README.md#privacy) |

[完整导航与组合](Sources/InnoDI/InnoDI.docc/DocumentationGuide.md) · [Assisted Factory / Collection](Sources/InnoDI/InnoDI.docc/Composition.md) · [InnoDITesting API](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)

<!-- innodi:section history -->
## 历史文档

[6.0.0 简体中文 README](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.zh-Hans.md) 仅用于查阅旧版本，请勿将其中的安装与使用说明直接套用于 7.0.1。
