# Policy Boundaries

InnoDI сохраняет детерминированность за счет явных границ.

## Matching Strategy

- общий nominal-path подход для макросов, Core и graph CLI
- поддержка вложенных путей вроде `Outer.Container`
- исключение generic argument extension и `where` extension
- неоднозначные случаи не приводят к спекулятивным совпадениям
