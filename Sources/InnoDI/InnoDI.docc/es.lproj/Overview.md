# ``InnoDI``

Inyección de dependencias basada en macros para Swift con validación en capas.

## Overview

InnoDI convierte tipos Swift normales en contenedores DI mediante
`@DIContainer` y `@Provide`. El paquete se centra en wiring explícito,
validación determinista y graph tooling.

La baseline estable de 4.0.0 incluye:

- APIs de contenedor generadas por macros
- validación en compilación y build
- render del grafo global y validación DAG
- aristas diferidas con `Lazy<T>` y `Provider<T>`
- `@SubContainer`, `@DIComponent` y `@DIHierarchyRoot`
- helpers de SwiftUI en `InnoDISwiftUI`

4.1.0 agrega hardening de release sobre esa baseline:

- fail-fast de unsafe filesystem para el lock del validation coordinator
- lock por capas con `O_CREAT | O_EXCL` mas `flock` en filesystems soportados
- diagnosticos de build-time en lugar de accessors `fatalError` sintetizados por macros
- PR/release gates que fuerzan strict concurrency y la allow-list de `fatalError` en macros
- guia key-path de `@SubContainer` para `withNames:` cuando no hay peer macros apilados

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

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
