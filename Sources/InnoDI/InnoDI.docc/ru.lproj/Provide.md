# Provide

`@Provide` объявляет член контейнера и стратегию его построения.

InnoDI 5.0 поддерживает `@Provide` только для прямого обычного хранимого
instance `var` в том же поддерживаемом `@DIContainer` struct. Отклоняются
`let`, computed/observed properties, `lazy`, `weak`, `unowned`,
`static`/`class`, самостоятельные и косвенно вложенные варианты. Сгенерированный
accessor принадлежит InnoDI; не прикрепляйте `_InnoDIProvideAccessor` вручную.

Также отклоняются property wrappers, условные или неизвестные attributes,
setter access modifiers вроде `private(set)` и пользовательские global-actor
attributes. Помимо `@Provide`, не допускаются никакие source-written attributes
уровня property, включая `@MainActor`. Запрашивайте actor isolation через
`@DIContainer(mainActor: true)`. Isolation attributes, которые InnoDI генерирует
на provider declaration и accessor, являются внутренней поддержкой компилятора.
Полное объявление member `@Provide` внутри `#if` приводит к
`provide.conditional-declaration-unsupported`; оставьте объявление вне условия
и выполняйте ветвление внутри factory или инжектируемой реализации.

Для одного property разрешен ровно один `@Provide`; duplicate attributes
отклоняются кодом `provide.duplicate-attribute`. Явный тип property не может
быть opaque `some Protocol` или implicitly unwrapped optional `T!`; используйте
соответственно `any Protocol` либо явный `T` / `T?`. Поддельная комбинация
compiler-support accessor с другим property wrapper может получить структурные
диагностики Swift в дополнение к диагностике misuse от InnoDI.

## Declaration

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    escaping: Bool = false
)
```

## Input values и escaping functions

Сгенерированные `.input` initializer parameters являются eager values
объявленного типа `T`. Swift вычисляет каждый argument до вызова initializer,
поэтому `try makeValue()` и `await makeValue()` остаются допустимыми argument
expressions. Прямо записанные non-optional function types определяются
автоматически и генерируются как escaping parameters. Если такой тип скрыт за
typealias, объявите `@Provide(.input, escaping: true)`.

`escaping:` должен быть literal Bool и допустим только для `.input`. Очевидные
nonfunction и optional-function shapes отклоняются стабильными диагностиками
InnoDI. Identifier/member types принимаются консервативно, потому что attached
macro не может разрешить произвольный alias; Swift может добавить собственную
диагностику, если alias не является non-optional function type.

## Rules

- `factory:`, `asyncFactory:`, `Type.self` и property initializer —
  взаимоисключающие construction sources
- `.input` не допускает construction sources и `with:`
- `.shared` и `.transient` требуют ровно один construction source
- `with:` разрешен только с `Type.self` и синхронными providers
- `asyncFactory` поддерживается для `.shared` и `.transient` и должен быть
  `async` closure
- Форма хранения определяется объявленным типом property: конкретный nominal
  type использует concrete storage, а `any Protocol` — existential storage

## Контракт sibling edges

- Только именованные параметры root literal closure `factory:` или
  `asyncFactory:` объявляют edges. Вложенные closures и произвольные identifiers
  не создают edges.
- `Type.self` объявляет edges из literal массива `with:`. Каждый элемент должен
  точно использовать canonical direct-member форму `\Self.member`, например
  `with: [\Self.config]`; `with: []` также допустим. Named container,
  module-qualified и typealias roots, nested components, optional chaining,
  subscripts и computed elements отклоняются. Все targets должны использовать
  синхронное construction.
- Factory, не являющаяся closure, и property initializer — непрозрачные
  zero-edge источники и не могут ссылаться на sibling members. Используйте
  параметры root closure или qualified global/static symbol.

## Совместимость эффектов provider

Эффекты factory задаются явно и не выводятся из зависимостей. Для асинхронного
consumer используйте `asyncFactory:`, а при потреблении асинхронного throwing
provider явно укажите для closure `async throws`. Совместимость проверяется и
при `validateDAG: false`.

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | разрешено | разрешено | разрешено |
| `async` | запрещено | разрешено | разрешено |
| `async throws` | запрещено | запрещено | разрешено |

`Lazy<T>` и `Provider<T>` остаются синхронными deferred wrappers. Оба отвергают
targets, создаваемые через `asyncFactory:`.
