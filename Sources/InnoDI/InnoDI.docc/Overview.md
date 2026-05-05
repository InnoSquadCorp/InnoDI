# ``InnoDI``

Macro-driven dependency injection for Swift with layered validation.

## Overview

InnoDI turns plain Swift types into DI containers through `@DIContainer` and
`@Provide`. The package focuses on explicit wiring, deterministic validation,
and graph tooling rather than runtime container mutation.

The generated API is intentionally initializer-centered. InnoDI does not ship
an `@Injected` property wrapper or a dynamic registration container; those
patterns are useful in runtime DI tools, but InnoDI optimizes for code-review
visibility, deterministic macro expansion, and build-time graph validation.

4.0.0 treats the following as the stable baseline:

- macro-generated container APIs
- compile-time and build-time validation
- global dependency-graph rendering and DAG validation
- `Lazy<T>` and `Provider<T>` deferred edges
- `@SubContainer`, `@DIComponent`, and `@DIHierarchyRoot`
- SwiftUI helpers in `InnoDISwiftUI`

4.1.0 adds release-hardening around that baseline:

- unsafe-filesystem fail-fast for the validation coordinator lock
- layered `O_CREAT | O_EXCL` plus `flock` locking on supported filesystems
- build-time diagnostics instead of macro-synthesized `fatalError` accessors
- shared parsed workspace snapshots across build validators
- in-process DAG validation from the build coordinator
- PR and release gates that both enforce strict concurrency and the
  macro-source `fatalError` allow-list
- `@SubContainer` key-path guidance for the non-stacked `withNames:` case

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

### Symbols

- ``DIContainer(root:validateDAG:mainActor:)``
- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
- ``Lazy``
- ``Provider``
