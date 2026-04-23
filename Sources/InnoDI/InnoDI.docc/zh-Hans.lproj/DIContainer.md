# DIContainer

`@DIContainer` 用来标记 InnoDI 容器并合成容器表面。

## 声明

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## 生成内容

- primary `init(...)`
- 嵌套 `Overrides`
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- 四个 `withOverrides` 重载

只要用户没有自己声明嵌套 `Overrides` 类型，所有容器都会生成 overrides
scaffolding。

## 参数

- `root`：只影响图渲染入口
- `validateDAG`：控制全局 DAG 校验与本地 cycle / closure-`with:` 校验
- `mainActor`：把生成的容器 API 隔离到 `@MainActor`
