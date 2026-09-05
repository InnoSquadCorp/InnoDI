# ``InnoDI``

Inyección de dependencias basada en macros para Swift con validación en capas.

## Overview

InnoDI convierte structs Swift compatibles, efectivamente no genéricos y de
alcance de archivo o anidados nominalmente en contenedores DI mediante
`@DIContainer` y `@Provide`. No admite declaraciones en ámbitos ejecutables o
locales, incluidas funciones, closures, accessors y casos de `switch`. El
paquete se centra en wiring explícito, validación determinista y graph tooling.

La baseline estable de 4.0.0 incluye:

- APIs de contenedor generadas por macros
- validación en compilación y build
- render del grafo global y validación DAG
- aristas diferidas con `Lazy<T>` y `Provider<T>`
- `@SubContainer` y roles de jerarquía explícitos con `@DIContainerRole`
- helpers de SwiftUI en `InnoDISwiftUI`

4.1.0 agrega hardening de release sobre esa baseline:

- fail-fast de unsafe filesystem para el lock del validation coordinator
- lock por capas con `O_CREAT | O_EXCL` mas `flock` en filesystems soportados
- diagnosticos de build-time en lugar de accessors `fatalError` sintetizados por macros
- PR/release gates que fuerzan strict concurrency y la allow-list de `fatalError` en macros
- `@SubContainer` usa solo `with:` para same-name wiring; el escape hatch `withNames:` fue eliminado

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
- ``Input(_:escaping:)``
- ``DIContainerRole(role:mainActor:validateDAG:)``
