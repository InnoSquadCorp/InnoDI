# DIContainer

`@DIContainer` помечает тип как контейнер InnoDI и синтезирует его API.

## Declaration

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

## Generated Surface

- primary `init(...)`
- вложенный `Overrides`
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- четыре overload `withOverrides`

Пока пользователь сам не объявил вложенный `Overrides`, scaffolding
генерируется для всех контейнеров.

## Parameters

- `root`: влияет только на вход рендера графа
- `validateDAG`: управляет global DAG validation и local cycle / closure-`with:`
- `mainActor`: добавляет `@MainActor` к сгенерированному API
