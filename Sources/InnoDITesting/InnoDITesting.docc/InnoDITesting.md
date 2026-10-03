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
`Overrides` conforms to an effect-validation protocol. For a container declared
with `generateOwned: true`, pass `preset.applyValidated` directly to the generated
`withPrepared` helper:

```swift
let offline = DIOverridePreset<AppContainer.Overrides>(name: "offline") {
    $0.set(\.apiClient, to: MockAPIClient())
}

let result = try await AppContainer.withPrepared(
    .service,
    overrides: offline.applyValidated
) { services in
    try await services.service
}
```

Strict validation finishes before construction. Only after it succeeds does the
helper construct the owned graph, require the selected asynchronous providers
to be ready, and run the operation. The helper awaits owner shutdown on both
success and failure. It does not automatically validate effects when passed an
ordinary override closure or when its override argument is omitted.

For manual construction or a custom policy, call
`validated(base:profile:)` before constructing the container:

```swift
let overrides = try offlinePreset.validated(base: AppContainer.Overrides())
let container = AppContainer { $0 = overrides }
```

The strict profile throws ``DIMissingEffectOverrideError`` before any live
factory runs. The recording profile returns the same sorted
``DIOverrideEffectReport`` without failing. InnoDI never guesses whether an
arbitrary closure has side effects, so unmarked providers remain unverified.

The error names the missing providers and explains how to repair the builder before
construction. For an optional replacement, use `set(_:to:)` with `nil`; assigning
`nil` to the optional override field means no replacement. The following complete
consumer is compiled and executed by the portable validation tool. Its counter
proves that failed validation and accepted replacements never invoke the live
factory:

<!-- diagnostic-recovery: Overrides -->
```swift
import InnoDITesting

final class LiveCounter {
    var calls = 0
    func make() -> Int? { calls += 1; return 41 }
}

@DIContainer
struct TestServices {
    @Input var counter: LiveCounter
    @Provide(.shared, effect: .sideEffect, factory: { (counter: LiveCounter) in counter.make() })
    var optional: Int?
}

@main enum Check {
    static func main() throws {
        let counter = LiveCounter()
        var overrides = TestServices.Overrides()
        do {
            try DIOverrideEffectValidation.validate(overrides)
            preconditionFailure("Expected missing override")
        } catch let error as DIMissingEffectOverrideError {
            precondition(error.report.missing.map(\.providerName) == ["optional"])
            precondition(error.description.contains("Overrides.set(_:to:)"))
            precondition(error.description.contains("validate before constructing"))
        }
        precondition(counter.calls == 0)

        overrides.set(\.optional, to: 7)
        try DIOverrideEffectValidation.validate(overrides)
        precondition(TestServices(counter: counter) { $0 = overrides }.optional == 7)

        overrides.set(\.optional, to: nil)
        try DIOverrideEffectValidation.validate(overrides)
        precondition(TestServices(counter: counter) { $0 = overrides }.optional == nil)
        precondition(counter.calls == 0)

        overrides.useDefault(\.optional)
        do {
            try DIOverrideEffectValidation.validate(overrides)
            preconditionFailure("The live default needs a replacement again")
        } catch is DIMissingEffectOverrideError {}
        precondition(counter.calls == 0)
    }
}
```
<!-- /diagnostic-recovery -->

### Explicit nil and default restoration

Generated override fields use an outer optional to mean “no replacement.”
`set(_:to:)` preserves an explicit `nil` for optional-valued providers, while
`useDefault(_:)` removes the replacement:

```swift
var overrides = AppContainer.Overrides()
overrides.set(\.optionalCache, to: nil) // Explicit nil: .some(nil).
overrides.useDefault(\.optionalCache) // No override: .none.
```

An explicit `nil` satisfies an effect-marked override requirement. Restoring its
default makes strict validation fail again. A transient override remains a
stored replacement value returned on every access; these helpers do not turn it
into a per-access replacement factory.

`applyValidated(to:)` mutates the caller's builder before validating it. If it
throws, those mutations remain in the builder; the construction helper still
does not construct a graph or run its operation.

### Main-actor overrides

Main-actor containers provide the same strict `applyValidated` adapter. Existing
presets retain their nonisolated `@Sendable` mutation closure, so use an isolated
throwing closure for actor-bound or non-`Sendable` values and generated slot
helpers:

```swift
@MainActor
func runPreview() async throws {
    let localClient = PreviewClient()
    try await AppContainer.withPrepared(
        .service,
        overrides: {
            $0.set(\.apiClient, to: localClient)
            try DIOverrideEffectValidation.validate($0)
        }
    ) { services in
        _ = try await services.service
    }
}
```

The slot helpers retain the builder's actor isolation. For an explicitly
recording setup, use `preset.validated(base: $0, profile: .recording)` inside the
override closure and assign the returned builder to `$0`; this intentionally
allows missing marked replacements and their live factories.

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
