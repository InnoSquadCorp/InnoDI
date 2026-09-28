# ``InnoDITesting``

Build concurrency-safe generated mocks and reusable dependency presets without
adding test frameworks or source-analysis libraries to production targets.

## Overview

Add `InnoDITesting` only to test or preview-support targets. A protocol that
inherits `Sendable` uses ``DIConcurrentValueBox`` in its generated mock, while
``DIConcurrentCallRecorder`` is available to hand-written mocks. Both provide
locked snapshots without unchecked conformance.

Generated mocks also expose typed `.calls` and `.all` reset scopes. Every call
record carries a generation, reset returns the atomic snapshot it closes, and
the current aggregate is available through `innoDICallHistorySnapshot`.
`Sendable` mocks route calls, snapshots, stub access, and reset through
``DIConcurrentMockState``; `@MainActor` mocks rely on actor serialization.

Typed-throws mocks expose `missingStubSelectors`, and every generated mock with
function requirements exposes `recordedCallCounts`. Validate those values with
``DIInteractionValidation`` before and after the operation. The default
``DITestEffectProfile/strict`` policy throws a structured error; the recording
profile returns the same report without failing the test.

``DIOverridePreset`` composes typed override mutations from left to right.
Each application starts from the caller's value, so presets do not introduce
global or task-local state.

For a provider declared with `@Provide(effect: .sideEffect, ...)`, its generated
`Overrides` conforms to an effect-validation protocol. Apply a preset and call
`validated(base:profile:)` on ``DIOverridePreset`` before constructing the container:

```swift
let overrides = try offlinePreset.validated(base: AppContainer.Overrides())
let container = AppContainer { $0 = overrides }
```

The strict profile throws ``DIMissingEffectOverrideError`` before any live
factory runs. The recording profile returns the same sorted
``DIOverrideEffectReport`` without failing. InnoDI never guesses whether an
arbitrary closure has side effects, so unmarked providers remain unverified.

## Topics

### Concurrent mock storage

- ``DIConcurrentValueBox``
- ``DIConcurrentCallRecorder``
- ``DIConcurrentMockState``

### Stub and interaction validation

- ``DIStubValidation``
- ``DIMissingStubError``
- ``DIInteractionValidation``
- ``DIInteractionReport``
- ``DIInteractionViolationError``
- ``DIInteractionConfigurationError``
- ``DIOverrideEffectValidation``
- ``DIOverrideEffectReport``
- ``DIMissingEffectOverrideError``
- ``DITestEffectProfile``
- ``DIEffectViolationPolicy``

### Typed override presets

- ``DIOverridePreset``
