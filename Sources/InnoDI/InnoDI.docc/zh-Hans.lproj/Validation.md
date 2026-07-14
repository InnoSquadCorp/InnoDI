# Validation

InnoDI 以多层方式校验依赖定义。

## Macro Validation

宏校验会检查：

- scope 规则
- `@Provide` 的直接、普通、存储型实例 `var` 位置
- 缺失的 factory
- 声明顺序
- 局部 cycle
- 严格名称解析
- 显式 sibling edge 的效果兼容性
- 非法的用户自定义 `init`

显式 sibling edge 只来自根 `factory:`/`asyncFactory:` closure literal 的具名
参数，或 `Type.self` 与 literal `with:` key path。非 closure factory 和
property initializer 是不透明的 zero-edge 构造源，不能引用 sibling member。

`validateDAG: false` 不会关闭声明校验或效果兼容性校验，只会跳过全局 DAG、
本地 cycle 及其他 graph-derived 校验。

## Build Validation

协调后的 build pipeline 增加：

1. cross-file `init` 校验
2. 语义引用检查
3. hierarchy 校验
4. DAG 校验
5. metrics 与 summary artifact 输出
