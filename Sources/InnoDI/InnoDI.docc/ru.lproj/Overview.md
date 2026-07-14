# ``InnoDI``

Макро-ориентированный Swift DI с многоуровневой валидацией.

## Overview

InnoDI превращает поддерживаемые, фактически необобщённые Swift-структуры,
объявленные на уровне файла или номинально вложенные, в DI-контейнеры через
`@DIContainer` и `@Provide`. Объявления в исполняемых или локальных контекстах,
включая функции, замыкания, аксессоры и ветви `switch`, не поддерживаются.
Основной акцент — явный wiring, детерминированная валидация и инструменты графа.

Стабильная baseline 4.0.0 включает:

- сгенерированные макросами API контейнеров
- проверки на этапе компиляции и сборки
- глобальный рендер графа и DAG validation
- `Lazy<T>` и `Provider<T>`
- `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`
- SwiftUI helper в `InnoDISwiftUI`

4.1.0 добавляет release hardening поверх этой baseline:

- unsafe-filesystem fail-fast для lock validation coordinator
- многоуровневый lock с `O_CREAT | O_EXCL` и `flock` на поддерживаемых файловых системах
- build-time diagnostics вместо macro-synthesized `fatalError` accessors
- PR/release gates, которые проверяют strict concurrency и macro-source `fatalError` allow-list
- `@SubContainer` использует только `with:` для same-name wiring; escape hatch `withNames:` удален

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:MigrationGuide>
