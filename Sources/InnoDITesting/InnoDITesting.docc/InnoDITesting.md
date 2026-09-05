# ``InnoDITesting``

Build concurrency-safe generated mocks and reusable dependency presets without
adding test frameworks or source-analysis libraries to production targets.

## Overview

Add `InnoDITesting` only to test or preview-support targets. A protocol that
inherits `Sendable` uses ``DIConcurrentValueBox`` in its generated mock, while
``DIConcurrentCallRecorder`` is available to hand-written mocks. Both provide
locked snapshots without unchecked conformance.

Typed-throws mocks expose `missingStubSelectors`, and every generated mock with
function requirements exposes `recordedCallCounts`. Validate those values with
``DIInteractionValidation`` before and after the operation. The default
``DITestEffectProfile/strict`` policy throws a structured error; the recording
profile returns the same report without failing the test.

``DIOverridePreset`` composes typed override mutations from left to right.
Each application starts from the caller's value, so presets do not introduce
global or task-local state.

## Topics

### Concurrent mock storage

- ``DIConcurrentValueBox``
- ``DIConcurrentCallRecorder``

### Stub and interaction validation

- ``DIStubValidation``
- ``DIMissingStubError``
- ``DIInteractionValidation``
- ``DIInteractionReport``
- ``DIInteractionViolationError``
- ``DIInteractionConfigurationError``
- ``DITestEffectProfile``
- ``DIEffectViolationPolicy``

### Typed override presets

- ``DIOverridePreset``
