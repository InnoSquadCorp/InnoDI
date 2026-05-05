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

- `@DIContainer` и `@Provide` генерируют API контейнера из обычных Swift-типов.
- Макро-валидация ловит локальные ошибки во время expansion.
- Build validation и graph CLI находят межфайловые, межмодульные и глобальные проблемы графа.
- `InnoDISwiftUI` уменьшает повторяющееся environment wiring на границе root.

InnoDI не является runtime state machine. Состояние времени выполнения должно
жить в слое приложения или во вспомогательных фреймворках вроде `InnoFlow`,
`InnoRouter` и `InnoNetwork`.
InnoDI намеренно не предоставляет property wrapper `@Injected` или API
dynamic registration. Его компромисс — явные generated initializers,
reviewable wiring и более ранняя validation.

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

Операторы могут обойти unsafe-filesystem fail-fast через
`INNODI_ALLOW_UNSAFE_LOCK=1`, но InnoDI все равно выводит audit warning, а
риск остается на этом build environment. Диагностика, шаги восстановления и
полная таблица файловых систем описаны в
[Lock Safety](Sources/InnoDI/InnoDI.docc/lock-safety.md).

## Установка

Добавьте InnoDI в `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "4.1.0")
]
```

Затем подключите нужные продукты:

```swift
.target(
    name: "YourApp",
    dependencies: [
        "InnoDI",
        "InnoDISwiftUI"
    ]
)
```

Если SwiftUI helper не нужен, достаточно `InnoDI`.

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

## Что читать дальше

1. [Overview](Sources/InnoDI/InnoDI.docc/ru.lproj/Overview.md)
2. [Validation](Sources/InnoDI/InnoDI.docc/ru.lproj/Validation.md)
3. [Policy Boundaries](Sources/InnoDI/InnoDI.docc/ru.lproj/PolicyBoundaries.md)
4. [Module-Wide Init Detection](Sources/InnoDI/InnoDI.docc/ru.lproj/ModuleWideInitDetection.md)
5. [RELEASING.md](RELEASING.md)
6. [ROADMAP.md](ROADMAP.md)

## Основной API

### `@DIContainer`

`@DIContainer` синтезирует:

1. primary `init(...)`
2. вложенный тип `Overrides`
3. convenience `init(<inputs...>, _ applyOverrides: ...)`
4. четыре overload `withOverrides` для `sync`, `throws`, `async` и `async throws`

Все контейнеры генерируют overrides scaffolding, если пользователь сам не
объявил вложенный тип `Overrides`.

| Параметр | По умолчанию | Значение |
|---|---|---|
| `root` | `false` | Флаг точки входа только для рендера графа. Если есть хотя бы один root, вывод Mermaid, DOT и ASCII сужается до узлов и ребер, достижимых от root. |
| `validateDAG` | `true` | Включает global DAG validation и локальные graph-derived проверки macro для cycle и closure/`with:`. При `false` отключается только этот объем; raw-expression ссылки в `factory:` и initializer по-прежнему диагностируются, а структурная валидация остается активной. |
| `mainActor` | `false` | Добавляет `@MainActor` к сгенерированному API контейнера. Рекомендуется для UI-root контейнеров. |

### `@Provide` и области действия

| Scope | Значение | Правила создания |
|---|---|---|
| `.input` | Внешняя зависимость, передаваемая при инициализации контейнера | Без `factory` и `asyncFactory` |
| `.shared` | Создается один раз на экземпляр контейнера и переиспользуется | Нужны `factory`, `asyncFactory` или `Type.self` плюс `with:` |
| `.transient` | Создается заново при каждом доступе | Нужны `factory`, `asyncFactory` или `Type.self` плюс `with:` |

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

Контейнеры только с `.input` тоже получают пустой builder. Если дочерний
контейнер input-only, closure `<name>Overrides` все равно компилируется и
выполняется как no-op.

## `Lazy<T>` и `Provider<T>`

- `Lazy<T>` создает soft edge и используется как выход из cycle detection.
- `Provider<T>` повторно входит в `.transient` зависимость при каждом вызове.

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
