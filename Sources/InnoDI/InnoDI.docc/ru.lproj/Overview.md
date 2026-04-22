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

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>
