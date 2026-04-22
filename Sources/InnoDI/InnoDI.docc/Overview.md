# ``InnoDI``

Macro-driven dependency injection for Swift.

## Overview

InnoDI generates container initialization and accessors from `@DIContainer` and `@Provide` declarations.
The goal is to keep DI wiring explicit while catching invalid graph configuration at compile/build time.
Optional hierarchy annotations extend the same model across modules:
`@DIComponent` marks a child container as mountable across module boundaries,
and `@DIHierarchyRoot` enables rooted workspace validation.

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
- <doc:Validation>

### Symbols

- ``DIContainer(root:validateDAG:mainActor:)``
- ``DIComponent()``
- ``DIHierarchyRoot()``
- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
