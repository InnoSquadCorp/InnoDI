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
использовании `@DIContainerRole` с ролью component. Состояние времени выполнения и
состояние, зависящее от конкретного типа, следует скрыть за protocol
dependencies или `@Input`.

Явно объявленный `private` container также отклоняется: sibling containers не
могут обращаться к его generated mount surface. Для mounting внутри файла
используйте `fileprivate` либо container с default access внутри private
namespace.

Текущий компилятор Swift не передаёт контекст аксессора при expansion attached
macro для типа внутри body вычисляемого свойства. Build-validation plugin и
dependency-graph CLI сканируют полное дерево исходного кода и отклоняют также
этот граничный случай. Подключайте plugin к каждому target, где объявлены
контейнеры.

## Declaration

```swift
@DIContainer(validateDAG: Bool = true)
@DIContainerRole(role: String, mainActor: Bool = false, validateDAG: Bool = true)
```

## Generated Surface

- primary `init(...)`
- вложенный `Overrides`
- convenience `init(<inputs...>, _ applyOverrides: ...)`
- четыре overload `withOverrides`

Для контейнера без `mainActor: true` сгенерированные методы `withOverrides`
с `async` и `async throws`, а также типы их operation closures имеют
`nonisolated(nonsending)`. Они сохраняют actor executor вызывающей стороны,
поэтому произвольные non-`Sendable` значения container и closure не пересекают
границу изоляции. Синхронные overload не меняются. При `mainActor: true` все
overload `withOverrides` и operation closures остаются `@MainActor`.

Каждый контейнер, даже без управляемых членов, генерирует полный overrides
scaffolding. Пользовательский вложенный тип `Overrides` не поддерживается в
InnoDI 6.0 и вызывает `container.overrides-name-conflict`; переименуйте его,
чтобы macro владел совместимым с mounting override ABI.

Macro также генерирует зарезервированный compiler-support alias
`_InnoDIMountOverrides = Overrides` для generated parent mounting code. Не
объявляйте и не используйте это имя с подчеркиванием напрямую.

Каждый хранимый instance member должен использовать `@Provide` или
`@SubContainer`; computed и type properties остаются доступными. Это позволяет
синтезированному initializer владеть всем состоянием и предотвращает дрейф
memberwise-initializer ABI.

Каждый `@Provide` должен быть прямым обычным хранимым instance `var` этого
struct. Accessor/observer, `let`, `lazy`, `weak`, `unowned`, `static`/`class`,
самостоятельные и косвенно вложенные providers отклоняются; сгенерированный
accessor нельзя прикреплять вручную.

Sibling edges создаются только именованными параметрами root literal closures
`factory:`/`asyncFactory:` либо `Type.self` с literal key paths `with:`.
Не-closure factory и property initializer — непрозрачные zero-edge источники и
не могут ссылаться на sibling members. Совместимость эффектов обязательна и
при `validateDAG: false`.

## Parameters

- `root`: влияет только на вход рендера графа
- `validateDAG`: управляет global DAG и local graph-derived проверками;
  `false` не отключает проверку деклараций и совместимость эффектов явных
  sibling edges
- `mainActor`: изолирует с помощью `@MainActor` аксессоры зависимостей, все
  сгенерированные инициализаторы, `Overrides`, типы замыканий `applyOverrides`
  для convenience initializer, `withOverrides`, overrides дочерних контейнеров
  и mounting компонентов, операционные замыкания всех четырёх overload
  `withOverrides` и feature-root helpers. При совместном использовании с
  роли component ту же изоляцию получают сгенерированные protocol
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
