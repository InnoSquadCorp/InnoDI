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
- `mainActor`: изолирует с помощью `@MainActor` аксессоры зависимостей, все
  сгенерированные инициализаторы, `Overrides`, типы замыканий `applyOverrides`
  для convenience initializer, `withOverrides`, overrides дочерних контейнеров
  и mounting компонентов, операционные замыкания всех четырёх overload
  `withOverrides` и feature-root helpers. При совместном использовании с
  `@DIComponent` ту же изоляцию получают сгенерированные protocol
  `<Container>Dependencies` и `init(dependencies:_:)`, а компонент получает
  отдельную conformance `_InnoDIMainActorComponentMountable`. Компоненты без
  этой опции продолжают использовать `_InnoDIComponentMountable`.
  Сгенерированные значения, не реализующие `Sendable`, должны оставаться на
  главном акторе: используйте caller с `@MainActor` либо создавайте и
  используйте их в одном блоке `MainActor.run`. Прямой `await` подходит для
  изолированной операции с `Sendable`-результатом, но не для переноса самого
  container за пределы актора.

## See Also

- <doc:Validation>
- <doc:Provide>
