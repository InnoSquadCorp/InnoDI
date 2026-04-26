# ``InnoDI``

Макро-ориентированный Swift DI с многоуровневой валидацией.

## Overview

InnoDI превращает обычные Swift-типы в DI-контейнеры через `@DIContainer` и
`@Provide`. Основной акцент — явный wiring, детерминированная валидация и
инструменты графа.

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
- `@SubContainer` Fix-it guidance для `withNames:` без stacked peer macros

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:MigrationGuide>
