# ``InnoDI``

Macro-driven dependency injection for Swift.

## Overview

InnoDI generates container initialization and accessors from `@DIContainer` and `@Provide` declarations.
The goal is to keep DI wiring explicit while catching invalid graph configuration at compile/build time.

## Topics

### Container API

- <doc:DIContainer>
- <doc:Provide>
- <doc:Validation>

### Symbols

- ``DIContainer(validate:root:validateDAG:mainActor:)``
- ``Provide(_:_:with:factory:asyncFactory:concrete:)``
- ``DIScope``
