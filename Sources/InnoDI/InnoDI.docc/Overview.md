# ``InnoDI``

Macro-driven dependency injection for Swift with layered validation.

## Overview

InnoDI turns plain Swift types into DI containers through `@DIContainer` and
`@Provide`. The package focuses on explicit wiring, deterministic validation,
and graph tooling rather than runtime container mutation.

4.0.0 treats the following as the stable baseline:

- macro-generated container APIs
- compile-time and build-time validation
- global dependency-graph rendering and DAG validation
- `Lazy<T>` and `Provider<T>` deferred edges
- `@SubContainer`, `@DIComponent`, and `@DIHierarchyRoot`
- SwiftUI helpers in `InnoDISwiftUI`

## Topics

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``DIComponent()``
- ``DIHierarchyRoot()``

### Symbols

- ``DIContainer(root:validateDAG:mainActor:)``
- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
- ``Lazy``
- ``Provider``
