# DIContainer

`@DIContainer` помечает поддерживаемую, фактически необобщённую структуру как
контейнер InnoDI и синтезирует его API.

`@DIContainer` поддерживает только фактически необобщённые объявления `struct`
на уровне файла или с номинальной вложенностью. Ни само объявление, ни любое
включающее его объявление не может иметь generic-параметров или условия
`where`. Отклоняются `class`, `actor`, `enum`, `protocol`, непосредственно
аннотированные `extension` и структуры, вложенные в extensions. Также
отклоняются объявления в любом исполняемом или локальном контексте, включая
функции, замыкания, аксессоры и ветви `switch`. То же ограничение действует при
совместном использовании `@DIComponent`. Состояние времени выполнения и
состояние, зависящее от конкретного типа, следует скрыть за protocol
dependencies или `@Provide(.input)`.

Текущий компилятор Swift не передаёт контекст аксессора при expansion attached
macro для типа внутри body вычисляемого свойства. Build-validation plugin и
dependency-graph CLI сканируют полное дерево исходного кода и отклоняют также
этот граничный случай. Подключайте plugin к каждому target, где объявлены
контейнеры.

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
генерируется для каждого поддерживаемого контейнера.

## Parameters

- `root`: влияет только на вход рендера графа
- `validateDAG`: управляет global DAG validation и local cycle / closure-`with:`
- `mainActor`: добавляет `@MainActor` к сгенерированному API

## See Also

- <doc:Validation>
- <doc:Provide>
