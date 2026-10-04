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

The latest stable release is 6.0.0. This source documentation describes the
unreleased 7.0 candidate; use the tagged documentation for a stable installation.
The package provides:

- macro-generated container APIs
- compile-time and build-time validation
- global dependency-graph rendering and DAG validation
- `Lazy<T>` and `Provider<T>` deferred edges
- `@SubContainer` and explicit `@DIContainerRole` hierarchy roles
- SwiftUI helpers in `InnoDISwiftUI`

The 7.0 candidate adds opt-in ownership and more explicit consumer contracts:

- `generateOwned: true`, selected async preparation, cancellation, retry and close
- `withPrepared`, which checks selected readiness and awaits cleanup
- typed prewarm selections and opt-in dependency initialization order
- explicit optional-nil/default override mutation and validated effect presets
- compiler-checked deferred captures and explicit feature-host imports

Construction and access remain macro-generated, typed Swift. Owned lifecycle
support coordinates concrete scopes; it does not resolve services by string.
See <doc:MigrationGuide> for breaking changes and <doc:OwnedContainers> for the
ownership boundaries. Passing a portable test subset does not replace the
supported Apple toolchain and release gates.

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

### Migrating from Other Libraries

- <doc:MigratingFromFactory>
- <doc:MigratingFromSwinject>

### Operations

- <doc:lock-safety>
- <doc:DAGValidation>
- <doc:AsyncPreparation>
- <doc:OwnedContainers>
- <doc:RuntimeTracing>
- <doc:PluginOptOut>
- <doc:MigrationGuide>

### Container API

- <doc:DIContainer>
- <doc:Provide>
- ``Input(_:escaping:)``
- ``DIContainerRole(role:mainActor:validateDAG:initializationOrder:generateOwned:)``

### Experimental

- <doc:AutoMock>

### SwiftUI Preview Helper

- <doc:SwiftUIPreviewHelper>

### Symbols

- ``DIContainer(validateDAG:initializationOrder:generateOwned:)``
- ``Provide(_:_:with:initialization:effect:collection:factory:asyncFactory:)``
- ``DIScope``
- ``Lazy``
- ``Provider``
- ``DIAsyncScope``
- ``DIAsyncPreparationPlan``
