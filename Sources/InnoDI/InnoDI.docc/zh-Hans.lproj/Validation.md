# Validation

InnoDI 以多层方式校验依赖定义。

## Macro Validation

宏校验会检查：

- scope 规则
- 缺失的 factory
- 声明顺序
- 局部 cycle
- 严格名称解析
- 非法的用户自定义 `init`

`validateDAG: false` 不会关闭结构性校验。

## Build Validation

协调后的 build pipeline 增加：

1. cross-file `init` 校验
2. 语义引用检查
3. hierarchy 校验
4. DAG 校验
5. metrics 与 summary artifact 输出
