# ``InnoDI``

Makrogetriebenes Swift-DI mit Validierung in mehreren Schichten.

## Overview

InnoDI macht aus normalen Swift-Typen mit `@DIContainer` und `@Provide`
vollwertige DI-Container. Im Mittelpunkt stehen explizites Wiring,
deterministische Validierung und Graph-Tooling.

Die stabile 4.0.0-Baseline umfasst:

- makrogenerierte Container-APIs
- Compile- und Build-Validierung
- globales Graph-Rendering und DAG-Validierung
- `Lazy<T>` und `Provider<T>`
- `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`
- SwiftUI-Helfer in `InnoDISwiftUI`

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
