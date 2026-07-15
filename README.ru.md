# InnoDI

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

InnoDI — это макро-ориентированный DI-фреймворк для Swift с проверками на
этапе компиляции и сборки, инструментами графа зависимостей, иерархической
валидацией и помощниками для SwiftUI.

## Минимальный полезный пример

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let client = AppContainer(baseURL: "https://api.example.com").apiClient
```

## Зачем нужен InnoDI

InnoDI подходит командам, которые хотят сохранить wiring DI явным и удобным
для ревью, обнаруживая ошибки как можно раньше.

- `@DIContainer` и `@Provide` генерируют API контейнера из поддерживаемых, фактически необобщённых Swift-структур.
- Макро-валидация ловит локальные ошибки во время expansion.
- Build validation и graph CLI находят межфайловые, межмодульные и глобальные проблемы графа.
- `InnoDISwiftUI` уменьшает повторяющееся environment wiring на границе root.

InnoDI не является runtime state machine. Состояние времени выполнения должно
жить в слое приложения или во вспомогательных фреймворках вроде `InnoFlow`,
`InnoRouter` и `InnoNetwork`.
InnoDI намеренно не предоставляет property wrapper `@Injected` или API
dynamic registration. Его компромисс — явные generated initializers,
reviewable wiring и более ранняя validation.

## Когда выбирать InnoDI

Выбирайте InnoDI, когда dependency wiring должен быть виден на code review,
проверяться до runtime и оставаться доступным для анализа как graph artifact.

| Если приоритет... | Предпочтите... | Почему |
| --- | --- | --- |
| Compile/build-time validation графа зависимостей приложения | InnoDI, [SafeDI](https://github.com/dfed/SafeDI) или [Needle](https://github.com/uber/needle) | InnoDI сохраняет container surface в macro-expanded Swift и добавляет локальные macro diagnostics, build-support checks и DAG CLI. |
| Runtime registration, late binding или plugin-like composition | [Swinject](https://github.com/Swinject/Swinject) или [Factory](https://github.com/hmlongco/Factory) | Runtime containers удобны для динамической замены registrations. InnoDI намеренно выбирает explicit generated initializers и early validation. |
| SwiftUI previews и scoped test overrides | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) или InnoDI | InnoDI лучше подходит, когда overrides должны стоять поверх validated app container и generated SwiftUI root helpers. |
| Hierarchical feature ownership и graph visibility | InnoDI, [Needle](https://github.com/uber/needle) или [SafeDI](https://github.com/dfed/SafeDI) | InnoDI моделирует parent-owned child containers через `@SubContainer` и показывает ownership edges в graph CLI. |
| Минимальная стоимость внедрения в существующую app | [Factory](https://github.com/hmlongco/Factory), [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) или incremental InnoDI adoption | InnoDI требует определить containers и принять macro/build validation; это окупается, когда нужны reviewable wiring, generated overrides и graph checks. |

На практике InnoDI может сосуществовать с runtime tools: используйте InnoDI
для validated application graph, а `swift-dependencies` или небольшие
factories внутри feature logic — для локальных runtime values.

Рабочий шаблон layering — отделить *конструирование* (InnoDI) от
*эфемерных, вызов-локальных override* (`swift-dependencies`). Composition root
разрешает `DependencyKey` (например `@Dependency(\.date)`) и передаёт
полученное значение в container как `.input`; тесты заменяют его на одно
дерево вызовов через `withDependencies { $0.date = .constant(...) }
operation:`, не пересобирая container и не перепроверяя его validated graph.
Container-level `Overrides` builder остаётся правильным инструментом для
app-wide swap (например подменить `APIClient`); `swift-dependencies` —
только когда override должен жить ровно одну operation.

## Требования

- Swift tools version `6.2` (CI проверяет Swift 6.2 и 6.3)
- Платформы:
  - iOS 17+
  - macOS 13+
  - watchOS 10+
  - tvOS 17+
  - visionOS 1+

### Требования build-time validator к файловой системе

Build plugin сериализует live DAG validation через многоуровневый POSIX lock
в scratch-директории Swift Package Manager:

1. `open(O_CREAT | O_EXCL | O_RDWR)` создает один lock file.
2. `flock(LOCK_EX | LOCK_NB)` добавляет advisory exclusive lock на descriptor.

InnoDI автоматически определяет файловую систему lock directory. Локальные
файловые системы APFS, HFS+, ext4, btrfs, xfs и tmpfs поддерживаются. NFS
mounts, SMB/CIFS, WebDAV и FUSE-подобные файловые системы по умолчанию
отклоняются, потому что concurrent builds могут повредить shared validation
cache, если lock atomicity ненадежна.

Если build system должна хранить derived data на shared volume, укажите
локальную директорию через SPM `--scratch-path` или настройку Xcode
derived-data location:

```sh
swift build --scratch-path /tmp/innodi-cache
```

Plugin не создает lock/cache state в package root
`.build/innodi-dag-validation`; перенос scratch path переносит и validation
state.

Операторы могут обойти unsafe-filesystem fail-fast через
`INNODI_ALLOW_UNSAFE_LOCK=1`, но InnoDI все равно выводит audit warning, а
риск остается на этом build environment. Диагностика, шаги восстановления и
полная таблица файловых систем описаны в
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md).

Валидатор времени сборки предоставляет два escape hatch для быстрой итерации
или ограниченных окружений: `@DIContainer(validateDAG: false)` на уровне
отдельного контейнера и `INNODI_DISABLE_BUILD_VALIDATION=1` для отключения
всего build plugin. Каждый PR запускает
`Tools/report-validate-dag-escape-hatches.sh`, который перечисляет все места
использования этих escape hatch в step summary workflow, так что разрастание
escape hatch остаётся видимым без отдельного CI gate. Production CI должен
оставлять обе переменные unset.

## Конфиденциальность

InnoDI поставляется с Apple Privacy Manifest (`PrivacyInfo.xcprivacy`) в двух
runtime-продуктах: `InnoDI` и `InnoDISwiftUI`. Манифест декларирует отсутствие
отслеживания пользователей, отсутствие доменов отслеживания, отсутствие
собираемых типов данных и отсутствие использования Required Reason API.
Инструменты времени сборки (InnoDIBuildSupport, dependency-graph CLI,
macro plugin) не встраиваются в приложения пользователей и поэтому не влияют
на манифест. При встраивании InnoDI в приложение iOS, watchOS, tvOS или
visionOS SwiftPM автоматически упаковывает манифест, и он отображается в
агрегированном отчёте о конфиденциальности приложения.

## Установка

Добавьте InnoDI в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.3.0")
]
```

Затем подключите нужные продукты:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ]
)
```

Добавляйте `InnoDISwiftUI` только если нужны SwiftUI helpers:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Включите build-time DAG validator, добавив plugin в каждый target, где
объявляются InnoDI containers или standalone `@DIEnvironmentBridge`.
Target-scoped full-source pass отклоняет невидимые для attached macro generated
qualifier shadows во включающих объявлениях и других source того же target, а
также видимые qualifier shadows с доступом `public` или `package` в
импортированных dependency targets. Он также отклоняет direct-extension
attachments и standalone local bridge targets до компиляции Swift:

Если generated site является class или вложен в class, первый inherited type —
позиция, которая может указывать superclass, — должен разрешаться через
source-visible declarations и typealiases. Первый inherited type, доступный
только в SDK или binary, неразрешенный либо неоднозначный, приводит к fail-closed
ошибке `generated-qualifier.inheritance-unverifiable`. Переместите generated
site в struct / enum или source-visible adapter либо сделайте superclass chain
доступной для target-scoped source snapshot. Этот preflight использует
консервативный syntactic index и не заменяет Swift type checker.

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI"
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

`InnoDIValidationTools` сейчас является неопубликованным scaffold сопутствующего
package. Checked-in artifact — это fail-safe placeholder, который намеренно
завершается ошибкой, а не пригодный к использованию prebuilt validator. Consumers
не должны добавлять эту dependency, пока public release не опубликует и не
проверит настоящий artifact. После такого release подключайте либо source plugin
выше, либо prebuilt plugin, но никогда оба; unsupported hosts и local package
development должны продолжать использовать source plugin.

## Быстрый старт

<!-- innodi:compile -->
```swift
import Foundation
import InnoDI

protocol APIClientProtocol {
    func fetch() async throws -> Data
}

struct APIClient: APIClientProtocol {
    let baseURL: String
    func fetch() async throws -> Data { Data() }
}

@DIContainer
struct AppContainer {
    @Provide(.input)
    var baseURL: String

    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: any APIClientProtocol
}

let container = AppContainer(baseURL: "https://api.example.com")
_ = container.apiClient
```

Используйте factory closure, когда имена или логика создания не совпадают с
`Type.self` плюс `with:`.

```swift
@Provide(.shared, factory: { (baseURL: String) in
    APIClient(baseURL: baseURL)
})
var apiClient: any APIClientProtocol
```

## Что читать дальше

1. [Overview](Sources/InnoDI/InnoDI.docc/ru.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/ru.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/ru.lproj/PolicyBoundaries.md)
4. [Anti-Patterns](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
5. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ru.lproj/ModuleWideInitDetection.md)
6. [RELEASING.md](RELEASING.md)
7. [ROADMAP.md](ROADMAP.md)

## Основной API

### `@DIContainer`

`@DIContainer` синтезирует:

1. primary `init(...)`
2. вложенный тип `Overrides`
3. convenience `init(<inputs...>, _ applyOverrides: ...)`
4. четыре overload `withOverrides` для `sync`, `throws`, `async` и `async throws`

Каждый контейнер, даже без управляемых членов, генерирует полный overrides
scaffolding. Пользовательский вложенный тип `Overrides` не поддерживается в
InnoDI 5.0 и вызывает `container.overrides-name-conflict`; переименуйте его,
чтобы macro владел совместимым с mounting override ABI.

Macro также генерирует зарезервированный compiler-support alias
`_InnoDIMountOverrides = Overrides` для generated parent mounting code. Не
объявляйте и не используйте это имя с подчеркиванием напрямую.

Каждый хранимый instance member контейнера должен использовать `@Provide` или
`@SubContainer`; computed и static properties остаются доступными. Это
сохраняет полноту сгенерированного initializer и предотвращает дрейф
memberwise-initializer ABI.

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

Явно объявленный `private` container также отклоняется: sibling containers не
могут обращаться к его generated mount surface. Для mounting внутри файла
используйте `fileprivate` либо container с default access внутри private
namespace.

Текущий компилятор Swift не передаёт контекст аксессора при expansion attached
macro для типа внутри body вычисляемого свойства. Build-validation plugin и
dependency-graph CLI сканируют полное дерево исходного кода и отклоняют также
этот граничный случай. Подключайте plugin к каждому target, где объявлены
контейнеры.

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Параметр | По умолчанию | Значение |
|---|---|---|
| `root` | `false` | Флаг точки входа только для рендера графа. Если есть хотя бы один root, вывод Mermaid, DOT и ASCII сужается до узлов и ребер, достижимых от root. |
| `validateDAG` | `true` | Включает global DAG validation и локальные graph-derived проверки macro. При `false` отключаются global DAG и локальные cycle-проверки, но продолжаются проверка деклараций и совместимость эффектов явных sibling edges. |
| `mainActor` | `false` | Изолирует с помощью `@MainActor` аксессоры зависимостей, все сгенерированные инициализаторы, `Overrides`, типы замыканий `applyOverrides` для convenience initializer, `withOverrides`, overrides дочерних контейнеров и mounting компонентов, операционные замыкания всех четырёх overload `withOverrides` и feature-root helpers. При совместном использовании с `@DIComponent` также изолируются сгенерированные protocol `<Container>Dependencies` и `init(dependencies:_:)`, а компонент получает отдельную conformance `_InnoDIMainActorComponentMountable`. Компоненты без этой опции продолжают использовать `_InnoDIComponentMountable`. Для использования вне главного актора требуется явный actor hop. Рекомендуется для корневых UI-контейнеров. |

В 5.0 generic helpers для mounting компонентов должны различать два marker
protocol. Сохраните `_InnoDIComponentMountable` для обычных компонентов, а для
компонентов с `mainActor: true` добавьте `@MainActor` overload с constraint
`_InnoDIMainActorComponentMountable` и `@MainActor` override closure.

Значения container/component, не реализующие `Sendable`, должны оставаться на
главном акторе: используйте caller с `@MainActor` либо создавайте и используйте
их в одном блоке `MainActor.run`. Прямой `await` подходит для изолированной
операции с `Sendable`-результатом, например операции `withOverrides`, но не для
переноса самого container за пределы актора.

### `@Provide` и области действия

InnoDI 5.0 поддерживает `@Provide` только для прямого обычного хранимого
instance `var` в том же поддерживаемом `struct` с `@DIContainer`. `let`,
computed/observed properties, `lazy`, `weak`, `unowned`, `static`/`class`,
самостоятельные и косвенно вложенные варианты отклоняются. Сгенерированный
provider accessor принадлежит InnoDI; не прикрепляйте `_InnoDIProvideAccessor`
вручную.

Attributes и access control объявления provider также образуют закрытый
контракт. Отклоняются property wrappers, условные или неизвестные attributes,
setter access modifiers вроде `private(set)` и пользовательские global-actor
attributes. Помимо `@Provide`, не допускаются никакие source-written attributes
уровня property, включая `@MainActor`. Запрашивайте actor isolation через
`@DIContainer(mainActor: true)`. Isolation attributes, которые InnoDI генерирует
на provider declaration и accessor, являются внутренней поддержкой компилятора.
Полное объявление member `@Provide` внутри `#if` также отклоняется
диагностикой `provide.conditional-declaration-unsupported`; оставьте объявление
вне условия и выполняйте ветвление внутри factory или инжектируемой реализации.

Для одного property разрешен ровно один `@Provide`; duplicate attributes
отклоняются кодом `provide.duplicate-attribute`. Имена direct provider property
и dependency parameter корневой factory closure должны быть уникальными внутри
каждой группы; duplicate identity отклоняется до генерации lookup или storage
code. Оба вида declaration должны использовать unescaped identifiers; в 5.0
backtick-escaped имена property и factory parameter отклоняются. Имя property с
`@SubContainer` также должно быть unescaped, поскольку из него формируются child
storage, overrides и идентификаторы root helper.

Сгенерированные storage/support declarations резервируют `_storage_`,
`_override_`, `_innoDI` и `_InnoDI`; точное имя прямого declaration `InnoDI`
также зарезервировано. `Swift`, `_Concurrency` и anchors SwiftUI bridge
зарезервированы в type namespace, видимом attached macro. Точная матрица 5.0
описана в [Migration Guide](Sources/InnoDI/InnoDI.docc/MigrationGuide.md).
Target-scoped full-source pass отклоняет declarations во внешнем scope или том
же target, а также видимые `public` / `package` declarations в импортированных
dependency targets, если они перекрывают generated qualifier, невидимый для
attached macro.
Для class bridge или enclosing class scan также проходит source-visible
superclass chain. Унаследованные type members `Swift` и `SwiftUI` отклоняются,
а унаследованный member `InnoDISwiftUI` безопасен. Declaration
`InnoDISwiftUI`, видимый напрямую или в lexical scope, остается
зарезервированным. Поскольку это консервативный syntactic index, первый
inherited type, доступный только в SDK или binary, неразрешенный либо
неоднозначный, приводит к fail-closed ошибке
`generated-qualifier.inheritance-unverifiable`, а не к предположению, что в
superclass нет shadow.

Явный тип property не может быть opaque `some Protocol` или implicitly
unwrapped optional `T!`; используйте
соответственно `any Protocol` либо явный `T` / `T?`. Намеренно поддельная
комбинация compiler-support accessor с другим property wrapper может получить
структурные диагностики Swift в дополнение к диагностике misuse от InnoDI.

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

| Scope | Значение | Правила создания |
|---|---|---|
| `.input` | Внешняя зависимость, передаваемая при инициализации контейнера | Не объявляет `factory:`, `asyncFactory:`, `Type.self`, property initializer или `with:` |
| `.shared` | Создается один раз на экземпляр контейнера и переиспользуется | Объявляет ровно один источник: `factory:`, `asyncFactory:`, `Type.self` или property initializer |
| `.transient` | Создается заново при каждом доступе | Объявляет ровно один источник: `factory:`, `asyncFactory:`, `Type.self` или property initializer |

Дополнительные правила:

- Для `.shared` / `.transient` четыре construction source — `factory:`,
  `asyncFactory:`, `Type.self` и property initializer — взаимоисключающие.
- `.input` отклоняет все construction sources и `with:`.
- Сгенерированные `.input` initializer parameters остаются eager values
  объявленного типа `T`; Swift как обычно вычисляет `try` / `await` argument
  expressions до вызова initializer. Прямо записанные non-optional function
  types определяются автоматически и генерируются как escaping parameters.
  Если non-optional function type скрыт за typealias, используйте
  `@Provide(.input, escaping: true)`. `escaping:` должен быть literal Bool и
  допустим только для `.input`. Очевидные nonfunction и optional-function
  shapes отклоняются; если консервативно принятый identifier/member alias на
  деле не является non-optional function, Swift может выдать собственную
  диагностику.
- `asyncFactory` поддерживается для `.shared` и `.transient` и должен быть
  `async` closure.
- `with:` разрешен только для construction через `Type.self`. Каждый элемент
  literal массива должен точно использовать canonical direct-member форму
  `\Self.member`, например `with: [\Self.config]`; `with: []` также допустим.
  Named container, module-qualified и typealias roots, а также nested
  components, optional chaining, subscripts и computed array elements
  отклоняются. Все указанные providers должны использовать синхронное construction.
- Форма хранения определяется объявленным типом property: конкретный nominal
  type использует concrete storage, а `any Protocol` — existential storage.
- Разрешение имен для параметров factory и `with:` wiring строго выполняется
  по именам members.

Sibling DI edges имеют закрытый синтаксис:

- Root literal closure `factory:` или `asyncFactory:` объявляет edge для
  каждого именованного параметра. Вложенные closures и произвольные identifiers
  не добавляют edges.
- Конструкция `Type.self` объявляет edges из literal массива canonical
  `\Self.member` key paths и может ссылаться только на синхронные providers.
- Выражение `factory:`, не являющееся closure, и property initializer — это
  непрозрачные zero-edge источники создания. Они не должны ссылаться на sibling
  members контейнера. Для DI используйте параметры root closure; если DI edge
  не нужен, используйте qualified global/static construction symbol.

Эффекты factory задаются явно и не выводятся из зависимостей. Для асинхронного
consumer используйте `asyncFactory:`, а при потреблении асинхронного throwing
provider явно укажите для closure `async throws`. Совместимость эффектов
проверяется для каждого явного edge даже при `validateDAG: false`.

| Provider | sync consumer | `async` consumer | `async throws` consumer |
|---|---:|---:|---:|
| sync | разрешено | разрешено | разрешено |
| `async` | запрещено | разрешено | разрешено |
| `async throws` | запрещено | запрещено | разрешено |

`Lazy<T>` и `Provider<T>` — синхронные deferred wrappers, поэтому они
отвергают асинхронные targets.

## Модель валидации

InnoDI валидирует в несколько слоев:

1. Macro validation
2. Build validation
3. Global DAG validation

`validateDAG: false` — это намеренно узкий opt-out. Он отключает global DAG и
локальные cycle/graph-derived проверки, но не проверку деклараций и не
совместимость эффектов явных sibling edges из root closure или `with:`.

## Overrides Builder

Сгенерированный builder `Overrides` позволяет тестам переопределять только те
члены, которые им действительно нужны.

```swift
let container = AppContainer(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
}
```

Или ограничьте override одной operation:

```swift
let result = try await AppContainer.withOverrides(baseURL: "https://test.example.com") { overrides in
    overrides.apiClient = MockAPIClient()
} operation: { container in
    try await container.apiClient.fetch()
}
```

Контейнеры только с `.input` тоже получают пустой builder. Если дочерний
контейнер input-only, closure `<name>Overrides` все равно компилируется и
выполняется как no-op.

## `Lazy<T>` и `Provider<T>`

- `Lazy<T>` создает soft edge и используется как выход из cycle detection.
- `Provider<T>` повторно входит в `.transient` зависимость при каждом вызове.

```swift
@Provide(.shared, factory: { (service: Lazy<Service>) in
    Consumer(service: service)
})
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
})
var logger: RequestLogger
```

Оба wrapper намеренно non-`Sendable`. Они также остаются синхронными и не
могут указывать на member с `asyncFactory`.

## Вложенные контейнеры и иерархия

`@SubContainer` моделирует дочерние контейнеры, которыми владеет родитель:

```swift
@SubContainer(
    scope: .shared,
    with: [\.config, \.apiClient],
    featureRoot: FeatureRootScene.self
)
var feature: FeatureContainer
```

Ключевые правила:

- `scope:` обязателен.
- Объявляйте ровно один `@SubContainer` на прямом, обычном, хранимом instance
  `var` в поддерживаемом parent `@DIContainer`, вне `#if`. Не поддерживаются
  wrappers, storage/accessor modifiers, неизвестные attributes и ручное
  прикрепление `InnoDI._InnoDISubContainerAccessor`.
- Неявное wiring по имени используется только как convenience, когда у
  родителя 0 или 1 кандидат `@Provide`. Если кандидатов несколько, добавьте
  явное wiring вместо того, чтобы полагаться на ошибки сгенерированного
  Swift initializer.
- `with:` пробрасывает явное одноименное подмножество или порядок. Это должен
  быть литеральный массив key path, который может прочитать макрос;
  runtime-переменные и вычисляемые элементы не
  поддерживаются.
- `with: []` — явно пустое подмножество, вызывает `Child()`.
- `bindings:` remap-ит child input label на другое имя member родителя.
- `featureRoot:` / `featureRoots:` создают SwiftUI root helpers на parent
  container без наложения еще одного peer macro на тот же property.
- Выбирайте ровно одну wiring form: `with:` или `bindings:`.
- `Overrides` родителя получает и слот полной замены (`feature`), и
  child-override closure (`featureOverrides`).

Для межмодульного ownership используются:

- `@DIComponent`
- `@DIHierarchyRoot`

## SwiftUI helper

`InnoDISwiftUI` предоставляет:

- `.innodi(container)`
- `@DIEnvironmentBridge`
- `@SubContainer(..., featureRoot:)` и `featureRoots:` создают стандартные или
  именованные feature-root helpers.
- В InnoDI 5.0 устаревший макрос совместимости `@DIFeatureRoot` удален.
  Замените его аргументами feature root у `@SubContainer`.

## CLI и release-информация

```bash
swift run InnoDI-DependencyGraph --root . --root-pruning all
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

Release notes и upgrade notes находятся в [RELEASING.md](RELEASING.md).

## Примеры

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
