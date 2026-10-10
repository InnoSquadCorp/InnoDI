# InnoDI

<!-- innodi:guide version=7.0.1 -->

[English](README.md) | [한국어](README.ko.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [简体中文](README.zh-Hans.md) | [日本語](README.ja.md) | [Русский](README.ru.md)

> Краткое актуальное руководство по **InnoDI 7.0.1**, а не полный перевод английского README или каталога DocC. Основной источник — [английский README](README.md); также доступен подробный [корейский README](README.ko.md). Ссылки на подробные статьи ведут к английским версиям; поддерживаемые корейские версии находятся в [ko.lproj](Sources/InnoDI/InnoDI.docc/ko.lproj).

InnoDI генерирует код внедрения зависимостей с помощью макросов Swift. Явные контейнеры, проверки при компиляции и сборке, а также граф зависимостей позволяют проверять связи при ревью. Динамической регистрации и обёртки свойства `@Injected` нет.

<!-- innodi:section requirements -->

## Требования

- Версия инструментов Swift **6.2 или новее**; CI проверяет Swift 6.2, 6.3 и 6.4
- Только платформы Apple: iOS 17+, macOS 14+, watchOS 10+, tvOS 17+, visionOS 1+
- Linux не собирается и не тестируется в CI; `InnoDITesting` безусловно импортирует модуль Apple `os`
- `swift-syntax` закреплён строго на версии **604.0.0**. Его нельзя разрешить в одном графе SwiftPM с Mockable 0.6.4, которому нужен диапазон `509.0.0..<604.0.0`
- Рабочий каталог SwiftPM для блокировок и кеша проверки должен находиться в локальной файловой системе, например APFS. NFS, SMB, WebDAV и FUSE по умолчанию отклоняются; см. [безопасность блокировок](Sources/InnoDI/InnoDI.docc/lock-safety.md)

<!-- innodi:section installation -->

## Установка и обязательный плагин проверки

Добавьте пакет и настройки целевого модуля в свой `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/InnoSquadCorp/InnoDI.git", from: "7.0.1")
]
```

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "InnoDI", package: "InnoDI")
    ],
    plugins: [
        .plugin(name: "InnoDIDAGValidationPlugin", package: "InnoDI")
    ]
)
```

`InnoDI` — основной продукт. Для вспомогательных API SwiftUI добавьте `.product(name: "InnoDISwiftUI", package: "InnoDI")`. `InnoDITesting` добавляйте только в тестовые модули или модули поддержки previews, которым нужны сгенерированные моки либо наборы переопределений.

**Каждый целевой модуль**, объявляющий контейнер InnoDI или отдельный `@DIEnvironmentBridge`, должен подключать `InnoDIDAGValidationPlugin`. Плагин — часть контракта корректности: он проверяет, в частности, инициализаторы в других файлах, затенение квалификаторов и глобальный граф. Для Xcode и Tuist следуйте [руководству по интеграции](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md#build-plugin).

`validateDAG: false` и `INNODI_DISABLE_BUILD_VALIDATION=1` — ограниченные исключения, а не обычная производственная конфигурация. В CI для production проверка при сборке должна оставаться включённой; точные границы описаны в [Plugin Opt-Out](Sources/InnoDI/InnoDI.docc/PluginOptOut.md).

<!-- innodi:section quickstart -->

## Минимальный пример

После установки этот пример, скопированный без изменений из английского README, создаёт обычный контейнер и контейнер с тестовым значением. Если целевой модуль по умолчанию использует изоляцию MainActor, явно пометьте контейнер `@MainActor` или `nonisolated`: макрос не может определить эту настройку сборки.

<!-- innodi:compile -->
```swift
import InnoDI

struct APIClient { let baseURL: String }

@DIContainer
struct AppContainer {
    @Input var baseURL: String
    @Provide(.shared, APIClient.self, with: [\Self.baseURL])
    var apiClient: APIClient
}

let live = AppContainer(baseURL: "https://api.example.com")
let test = AppContainer(baseURL: "https://api.example.com") {
    $0.apiClient = APIClient(baseURL: "https://test.example.com")
}
precondition(live.apiClient.baseURL == "https://api.example.com")
precondition(test.apiClient.baseURL == "https://test.example.com")
```

<!-- innodi:section api -->

## Выбор API по задаче

| Задача | API и важное ограничение |
| --- | --- |
| Объявить контейнер | `@DIContainer` для поддерживаемых структур, фактически не являющихся обобщёнными; `@DIContainerRole` для явных ролей, компонентов и корней |
| Передать внешние значения | `@Input`; без фабрики, `Type.self`, инициализатора свойства и `with:` |
| Повторно использовать зависимость | `@Provide(.shared, ...)`; немедленное создание по умолчанию, либо первый доступ с `initialization: .onDemand` |
| Создавать при каждом доступе | `@Provide(.transient, ...)` |
| Связать члены одного контейнера | Именованные параметры корневого замыкания фабрики либо `Type.self` с литералом массива вроде `with: [\Self.baseURL]`; такие key path могут ссылаться только на синхронные провайдеры |
| Отложить синхронный доступ | `Lazy<T>`; следует области жизни целевого провайдера и не имеет собственного кеша |
| Многократно вызывать transient-провайдер | `Provider<T>`; требует синхронный целевой провайдер `.transient` |
| Владеть дочерними контейнерами | `@SubContainer`; явно задавать иерархию и привязки входных значений |
| Управлять готовностью, повтором и закрытием | `generateOwned: true`, `makeOwned`, `prepare`, `requireReady`, `withPrepared` |
| Подключить SwiftUI | `InnoDISwiftUI`, `@DIEnvironmentBridge` и генерируемые вспомогательные API корней функциональных модулей |

Для `.shared` и `.transient` выбирайте ровно один источник создания: `factory:`, `asyncFactory:`, `Type.self` или инициализатор свойства. Эффекты фабрики задаются явно: используйте `asyncFactory:` и при необходимости указывайте `async throws`. Они не выводятся из зависимостей.

`Lazy<T>` и `Provider<T>` синхронны и не являются `Sendable`; они не могут ссылаться на `asyncFactory` и должны оставаться в исходном домене изоляции. Они не разрывают циклы владения. Даже при `validateDAG: false` сохраняются проверки циклов владения, объявлений и совместимости эффектов на явных связях.

<!-- innodi:section lifecycle -->

## Асинхронная готовность и время жизни

- Обычный `.shared`-провайдер с `asyncFactory:` запускает задачу уже в инициализаторе. Такой контейнер не отменяет её автоматически
- У асинхронного `.shared`-провайдера с `initialization: .onDemand` работа начинается с первого доступа. Доступ всегда может выбросить ошибку; `closeAsyncProviders()` закрывает эти провайдеры и отменяет выполняющуюся работу. Копии контейнера разделяют логический кеш, а независимо инициализированные контейнеры изолированы друг от друга
- `generateOwned: true` создаёт отдельного владельца и представление контейнера. `makeOwned` имеет сигнатуру `async throws`, но **не означает готовность**. После `prepare` обязательно проверяйте `report.isReady`; `requireReady` выбрасывает ошибку, если результат не готов
- `withPrepared` вызывает операцию только после подготовки выбранного подграфа и затем дожидается `close()`, в том числе при ошибке. Не выбранные провайдеры с немедленным запуском всё равно могут работать или завершиться ошибкой
- Отмена ожидающего вызывающего кода прекращает только его ожидание, а не общую работу. Явный повтор применяется к завершившимся ошибкой или отменённым провайдерам; `retryAndRequireReady` не обновляет готовые значения и не запускает автоматический цикл повторов
- `await owner.close()` окончательно закрывает владельца, запрещает последующие асинхронные обращения, включая чтение из кеша, и запрашивает отмену работы во владении контейнера. Он не ждёт фабрики, игнорирующие отмену, не вызывает `shutdown()` сервисов и не отзывает уже возвращённые значения. Заимствованные входные значения, синхронные значения и дочерние контейнеры остаются заимствованными
- Автоматического закрытия при выходе из области видимости нет. Пользовательские методы и соответствия протоколам исходного контейнера не переносятся в представление владельца

Подробнее: [Owned Containers](Sources/InnoDI/InnoDI.docc/OwnedContainers.md) и [асинхронная подготовка](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md). В SwiftUI закрывайте владельца в реальной точке завершения времени жизни, а не безусловно в `onDisappear`.

<!-- innodi:section testing -->

## Тесты, переопределения и previews

Минимальный пример заменяет `apiClient` через сгенерированный builder `Overrides`. Для одной операции `withOverrides` предоставляет синхронный, синхронный с ошибками, асинхронный и асинхронный с ошибками варианты. Объявлять собственный вложенный тип `Overrides` нельзя.

`InnoDITesting` опционально добавляет генерируемые моки, безопасное при конкурентном доступе хранилище состояния, сброс с учётом поколений, проверку взаимодействий и типизированные наборы переопределений. Объявления и ограничения приведены в [Auto Mock](Sources/InnoDI/InnoDI.docc/AutoMock.md), а previews — в [SwiftUI Preview Helper](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md).

<!-- innodi:section diagnostics -->

## Диагностика, миграция и CI

Запускайте команды из репозитория InnoDI; в `--root` укажите анализируемый workspace. Команда тестирования проверяет пакет в текущем каталоге на поддерживаемой платформе Apple:

```bash
swift run InnoDI-Doctor --root /path/to/consumer
swift run InnoDI-Migrate --root /path/to/consumer --check
swift run InnoDI-Migrate --root /path/to/consumer --report --output migration-report.json
swift run InnoDI-DependencyGraph --root /path/to/consumer --validate-dag
swift run InnoDI-DependencyGraph --root /path/to/consumer --root-pruning all
swift run InnoDI-DependencyGraph --diff before.json after.json --check-contract
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
```

`swift run` может сначала собрать инструмент. Сам анализ Doctor в режиме по умолчанию остаётся доступом только на чтение.

По умолчанию Doctor работает только на чтение: не разрешает зависимости, не запускает сборку и не удаляет кеши. Динамические манифесты и неполные сопоставления Tuist не считаются успешной проверкой. Отчёт миграции использует коды завершения `0` — изменений не требуется, `1` — нужны изменения, `2` — проверка заблокирована. `--check-contract` возвращает `5` при изменении контракта графа; `before.json` и `after.json` должны быть существующими JSON-артефактами графа для целевых модулей.

До миграции с записью файлов изучите отчёт и [руководство по миграции](Sources/InnoDI/InnoDI.docc/MigrationGuide.md#6x--70). При использовании `--apply` проверяйте указанные файлы `RECOVERY` после закрытия редакторов и до их удаления. Единый источник примечаний к выпускам — [changelog](CHANGELOG.md#701).

<!-- innodi:section documentation -->

## Подробные руководства по задачам

Ниже приведены канонические английские статьи. Поддерживаемые корейские версии находятся в [ko.lproj](Sources/InnoDI/InnoDI.docc/ko.lproj); эта страница не обещает полного русского каталога DocC для 7.0.1.

- [Разобраться в основных понятиях](Sources/InnoDI/InnoDI.docc/Overview.md)
- [Создать первый контейнер](Sources/InnoDI/InnoDI.docc/Tutorial-01-Hello.md)
- [Передать входные значения](Sources/InnoDI/InnoDI.docc/Tutorial-02-Inputs.md)
- [Связать зависимости](Sources/InnoDI/InnoDI.docc/Tutorial-03-Wiring.md)
- [Использовать конкретные типы](Sources/InnoDI/InnoDI.docc/Tutorial-04-Concrete.md)
- [Создать дочерние контейнеры](Sources/InnoDI/InnoDI.docc/Tutorial-05-SubContainer.md)
- [Проверить правила контейнеров](Sources/InnoDI/InnoDI.docc/DIContainer.md)
- [Выбрать провайдеры и области жизни](Sources/InnoDI/InnoDI.docc/Provide.md)
- [Управлять асинхронными контейнерами через владельца](Sources/InnoDI/InnoDI.docc/OwnedContainers.md)
- [Спланировать подготовку и повтор](Sources/InnoDI/InnoDI.docc/AsyncPreparation.md)
- [Написать моки и тесты](Sources/InnoDI/InnoDI.docc/AutoMock.md)
- [Подключить SwiftUI и previews](Sources/InnoDI/InnoDI.docc/SwiftUIPreviewHelper.md)
- [Интегрировать SwiftPM, Xcode и Tuist](Sources/InnoDI/InnoDI.docc/IntegrationGuide.md)
- [Разобраться в проверках](Sources/InnoDI/InnoDI.docc/Validation.md)
- [Проверить глобальные графы](Sources/InnoDI/InnoDI.docc/DAGValidation.md)
- [Устранить диагностические сообщения](Sources/InnoDI/InnoDI.docc/DiagnosticsGuide.md)
- [Проверить инициализаторы в разных файлах](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md)
- [Оценить исключения для плагина](Sources/InnoDI/InnoDI.docc/PluginOptOut.md)
- [Понять границы проверок](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md)
- [Избежать антипаттернов](Sources/InnoDI/InnoDI.docc/AntiPatterns.md)
- [Проверить блокировки и файловые системы](Sources/InnoDI/InnoDI.docc/lock-safety.md)
- [Отследить разрешение зависимостей во время выполнения](Sources/InnoDI/InnoDI.docc/RuntimeTracing.md)
- [Перейти с 6.x на 7.0](Sources/InnoDI/InnoDI.docc/MigrationGuide.md)
- [Перейти с Factory](Sources/InnoDI/InnoDI.docc/MigratingFromFactory.md)
- [Перейти со Swinject](Sources/InnoDI/InnoDI.docc/MigratingFromSwinject.md)
- [Найти подходящее руководство](Sources/InnoDI/InnoDI.docc/DocumentationGuide.md)
- [Составить assisted-фабрики и коллекции](Sources/InnoDI/InnoDI.docc/Composition.md)
- [Изучить API InnoDITesting](Sources/InnoDITesting/InnoDITesting.docc/InnoDITesting.md)

<!-- innodi:section history -->

Историческая версия: [русский README для 6.0.0](https://github.com/InnoSquadCorp/InnoDI/blob/6.0.0/README.ru.md). Этот архивный документ не описывает текущий API.
