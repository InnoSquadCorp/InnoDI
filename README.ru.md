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
    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
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

- Swift tools version `6.2`
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
объявляются InnoDI containers:

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

Для команд, которые измерили, что компиляция source tool является основной
стоимостью внедрения, сопутствующий package `InnoDIValidationTools`
предоставляет optional prebuilt macOS validation plugin. Подключайте либо
source plugin выше, либо prebuilt plugin, но никогда оба; unsupported hosts и
local package development должны продолжать использовать source plugin.

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

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL])
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

Каждый поддерживаемый контейнер генерирует overrides scaffolding, если
пользователь сам не объявил вложенный тип `Overrides`.

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

```swift
@DIContainer(root: Bool = false, validateDAG: Bool = true, mainActor: Bool = false)
```

| Параметр | По умолчанию | Значение |
|---|---|---|
| `root` | `false` | Флаг точки входа только для рендера графа. Если есть хотя бы один root, вывод Mermaid, DOT и ASCII сужается до узлов и ребер, достижимых от root. |
| `validateDAG` | `true` | Включает global DAG validation и локальные graph-derived проверки macro для cycle и closure/`with:`. При `false` отключается только этот объем; raw-expression ссылки в `factory:` и initializer по-прежнему диагностируются, а структурная валидация остается активной. |
| `mainActor` | `false` | Добавляет `@MainActor` к сгенерированному API контейнера. Рекомендуется для UI-root контейнеров. |

### `@Provide` и области действия

```swift
@Provide(
    _ scope: DIScope = .shared,
    _ type: Any.Type? = nil,
    with dependencies: [AnyKeyPath] = [],
    factory: Any? = nil,
    asyncFactory: Any? = nil,
    concrete: Bool = false
)
```

| Scope | Значение | Правила создания |
|---|---|---|
| `.input` | Внешняя зависимость, передаваемая при инициализации контейнера | Без `factory` и `asyncFactory` |
| `.shared` | Создается один раз на экземпляр контейнера и переиспользуется | Нужны `factory`, `asyncFactory` или `Type.self` плюс `with:` |
| `.transient` | Создается заново при каждом доступе | Нужны `factory`, `asyncFactory` или `Type.self` плюс `with:` |

Дополнительные правила:

- `factory` и `asyncFactory` являются взаимоисключающими.
- `asyncFactory` должен быть `async` closure.
- Для concrete `.shared` и `.transient` storage требуется `concrete: true`.
- Разрешение имен для параметров factory и `with:` wiring строго выполняется
  по именам members.

## Модель валидации

InnoDI валидирует в несколько слоев:

1. Macro validation
2. Build validation
3. Global DAG validation

`validateDAG: false` — это намеренно узкий opt-out. Он отключает только global
DAG validation и локальные cycle / closure-`with:` graph-derived проверки
макроса. Структурная валидация и compile-time диагностика raw-expression
ссылок продолжают работать.

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
}, concrete: true)
var consumer: Consumer
```

```swift
@Provide(.shared, factory: { (requests: Provider<Request>) in
    RequestLogger(requests: requests)
}, concrete: true)
var logger: RequestLogger
```

Оба wrapper намеренно non-`Sendable`.

## Вложенные контейнеры и иерархия

`@SubContainer` моделирует дочерние контейнеры, которыми владеет родитель:

```swift
@SubContainer(scope: .shared, with: [\.config, \.apiClient])
var feature: FeatureContainer
```

Ключевые правила:

- `scope:` обязателен.
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
- `@DIFeatureRoot`

## CLI и release-информация

```bash
swift run InnoDI-DependencyGraph --root .
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/generate-docc.sh
```

Release notes и upgrade notes находятся в [RELEASING.md](RELEASING.md).

## Примеры

- [Examples/README.md](Examples/README.md)
- [Examples/SwiftUIExample](Examples/SwiftUIExample)
- [Examples/PreviewInjectionExample](Examples/PreviewInjectionExample)
- [Sources/InnoDIExamples/main.swift](Sources/InnoDIExamples/main.swift)
