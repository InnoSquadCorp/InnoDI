# 集成指南

InnoDI 将生成的 Swift 源码与构建期验证一起使用。多数工具在把宏输出视为
compiler-generated implementation detail、并把用户手写的 container 声明作为 review
surface 保留下来时效果最好。

## Periphery

- 针对生成后的 build settings 运行 Periphery，而不是手写 source globs，这样
  macro-expanded members 才能被编译器看到。
- 如果 `@DIContainer`、`@Provide`、`@SubContainer` 和 generated override entry points
  只通过 reflection-free wiring 调用，请通过 tests、sample apps 或 explicit retention
  rules 保持它们 reachable。
- 降低 generated-member noise 时，优先 retain container type 或其 public entry points，
  而不是忽略整个 module。

## SwiftLint

- 对用户手写 source 正常 lint。
- 不要把 macro-expanded output 当作 hand-written code 来 lint。
- 如果配置会检查 generated interface artifacts，请排除 InnoDI 的 reserved generated prefixes:
  `_storage_`, `_override_`, `_innoDI`, `_InnoDI`.

## SwiftFormat

- 格式化你手写的 container declarations。
- 不要要求 consumer projects 对 macro expansion snapshots 额外运行 formatting pass。
- 让 attributes 和 factory closures 在声明处保持可读；这是 reviewers 应该检查的 source surface。

## 宏生成成员

InnoDI 会根据 container declarations 生成 initializers、storage、overrides 和 helper closures。
这些 generated members 应视为 compiled API surface 的一部分，但 manual dependencies 仍应在
source container 中显式表达。

当工具报告 generated symbol 时，先把它映射回最近的 `@DIContainer`、`@Provide` 或
`@SubContainer` 声明，再判断该报告是否 actionable。

## 构建插件

为每个声明 containers 的 target 附加 `InnoDIDAGValidationPlugin`。plugin 现在通过 build
coordinator in-process 运行 DAG validator；standalone `InnoDI-DependencyGraph`
executable 仍可用于 local inspection 和 CI artifacts。

当 derived data 位于 network volume 时，请使用 local SwiftPM scratch path。scratch path
必须位于 local disk 且 writable；必要时请根据 OS 或 CI 环境将 `/tmp` 替换为合适的 local
temporary directory。

```sh
swift build --scratch-path /tmp/innodi-cache
```

filesystem 分类和 lock recovery 请参阅 <doc:lock-safety>。
