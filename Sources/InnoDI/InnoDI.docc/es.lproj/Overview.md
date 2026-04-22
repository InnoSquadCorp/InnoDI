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

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``
