# Policy Boundaries

InnoDI 通过显式边界来保持校验的确定性。

## Matching Strategy

- 宏、Core 与 graph CLI 尽量共享同一个 nominal-path 模型
- 支持 `Outer.Container` 这类嵌套路径
- 排除带泛型参数的 extension 与带 `where` 的 extension
- 模糊情况不会做推测性匹配
