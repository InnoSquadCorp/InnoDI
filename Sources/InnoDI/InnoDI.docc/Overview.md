# ``InnoDI``

Macro-driven dependency injection for Swift with layered validation.

## Overview

InnoDI turns supported, effectively non-generic Swift structs declared at file
scope or inside non-generic nominal declarations into DI containers through
`@DIContainer` and `@Provide`. Declarations in executable scopes are rejected.
The package focuses on explicit wiring, deterministic validation, and graph
tooling rather than runtime container mutation.

The generated API is intentionally initializer-centered. InnoDI does not ship
an `@Injected` property wrapper or a dynamic registration container; those
patterns are useful in runtime DI tools, but InnoDI optimizes for code-review
visibility, deterministic macro expansion, and build-time graph validation.

4.0.0 treats the following as the stable baseline:

- macro-generated container APIs
- compile-time and build-time validation
- global dependency-graph rendering and DAG validation
- `Lazy<T>` and `Provider<T>` deferred edges
- `@SubContainer` and explicit `@DIContainerRole` hierarchy roles
- SwiftUI helpers in `InnoDISwiftUI`

4.1.0 adds release-hardening around that baseline:

- unsafe-filesystem fail-fast for the validation coordinator lock
- layered `O_CREAT | O_EXCL` plus `flock` locking on supported filesystems
- build-time diagnostics instead of macro-synthesized `fatalError` accessors
- shared parsed workspace snapshots across build validators
- in-process DAG validation from the build coordinator
- PR and release gates that both enforce strict concurrency and the
  macro-source `fatalError` allow-list
- compiled documentation snippet checks in CI
- `@SubContainer` same-name wiring through `with:` only; the string-based
  `withNames:` escape hatch has been removed

## Topics

### Tutorials

- <doc:GettingStarted>
- <doc:Tutorial-01-Hello>
- <doc:Tutorial-02-Inputs>
- <doc:Tutorial-03-Wiring>
- <doc:Tutorial-04-Concrete>
- <doc:Tutorial-05-SubContainer>

### Start Here

- <doc:Validation>
- <doc:PolicyBoundaries>
- <doc:AntiPatterns>
- <doc:IntegrationGuide>
- <doc:ModuleWideInitDetection>
- <doc:DiagnosticsGuide>

### Operations

- <doc:lock-safety>
- <doc:DAGValidation>
- <doc:AsyncPreparation>
- <doc:RuntimeTracing>
- <doc:PluginOptOut>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``Input(_:escaping:)``
- ``DIContainerRole(role:mainActor:validateDAG:)``

### Experimental

- <doc:AutoMock>

### SwiftUI Preview Helper

- <doc:SwiftUIPreviewHelper>

### Symbols

- ``DIContainer(validateDAG:)``
- ``Provide(_:_:with:initialization:effect:collection:factory:asyncFactory:)``
- ``DIScope``
- ``Lazy``
- ``Provider``
- ``DIAsyncScope``
- ``DIAsyncPreparationPlan``
