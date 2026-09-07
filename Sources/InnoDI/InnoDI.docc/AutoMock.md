# Auto Mock Generation

`@GenerateMock` (RFC 0001) synthesizes a call-recording mock peer for a
protocol so tests can plug into the existing `Overrides` builder without
hand-writing the mock body. The attribute is available as an
**experimental** opt-in and remains experimental in InnoDI 6.0. Its generated
shape may evolve until RFC 0001's dedicated GA criteria pass.

## Usage

Attach `@GenerateMock` directly to a protocol declaration:

```swift
import InnoDI

@GenerateMock
protocol UserService {
    var prefix: String { get set }
    func fetch(id: String) async throws -> String
    func reset()
}
```

The macro emits a peer mock class next to the protocol. The generated class
conforms to the protocol. Tests instantiate the mock, populate the stubs, and
read recorded calls back:

```swift
let mock = UserServiceMock()
mock.prefix = "test"
mock.fetchResult = .success("hello")
try DIStubValidation.requireAllStubbed(mock.missingStubSelectors)

let value = try await mock.fetch(id: "42")
#expect(value == "hello")
#expect(mock.fetchCalls.last?.id == "42")

mock.reset()
#expect(mock.resetCalls.count == 1)

let completed = mock.innoDIReset(.calls)
#expect(completed.generation == 0)
#expect(completed.recordedCallCounts["reset"] == 1)
```

## Generated shape

For each supported protocol member the macro emits the following:

* **`var prop: T { get set }`** — an exact-typed computed `var prop: T`
  backed by private optional stub storage; populate before reading.
* **`func name(args)` (sync, non-throwing)** — a `struct NameCall`
  capturing the arguments, a `private(set) var nameCalls: [NameCall]`
  list, an optional `var nameReturnValue: ReturnType?` slot, and the
  conforming method which appends to `nameCalls` and unwraps the stub.
* **`func name(args) async`** — same as the sync case but with the
  `async` effect on the generated method.
* **`func name(args) throws -> T`** — replaces the optional return
  slot with `var nameResult: Result<T, Error> = .failure(...)` so
  tests choose between `.success(value)` and `.failure(error)` with
  one assignment. The default failure surfaces a nested
  `_InnoDIMockNotStubbed` error that prints the unstubbed selector
  name.
* **`func name(args) throws` (Void return)** — adds a single
  `var nameThrownError: Error?` hook the generated body re-throws when
  set. Assign `nil` explicitly to mark the success behavior as configured.
* **`func name(args) async throws -> T`** — combines the two cases.
* **`func name(args) throws(Failure) -> T`** — preserves the typed error in
  `Result<T, Failure>?`. Because the macro cannot invent an arbitrary
  `Failure`, validate `missingStubSelectors` before running the operation.
* **Overloaded functions** — helper names include selector labels and parameter
  type stems so `fetch(id:)` and `fetch(page:)` do not collide.
* **Generic functions** — the generated method preserves generic clauses and
  stores an erased `([Any]) -> Any` handler, with matching `async` / `throws`
  effects when needed. Tests cast through the generic return type at the call
  boundary. Generic typed-throws requirements remain unsupported because
  erasing their handler would lose the declared failure type.
* **`mutating` requirements** — supported through the generated `final class`
  mock; the synthesized method does not need to be marked `mutating`.
* **Access level** — mocks for `private` and `fileprivate` protocols inherit
  that narrow access so the generated conformance remains legal. Mocks for
  internal, package, and public protocols remain internal while this API is
  experimental; attaching the macro never expands a package's public API.
* **Escaping closure arguments** — recorded with property-safe function types
  (`@escaping` / `@autoclosure` are removed from the call-record field while
  the conforming method keeps the original parameter spelling).
* **Concurrency** — a protocol inheriting `Sendable` receives lock-backed call
  and stub storage from the `InnoDITesting` product. Snapshots and reset-safe
  support types do not use unchecked conformance. The compiler still rejects
  non-`Sendable` arguments, results, and stored properties. Ordinary protocols
  remain single-executor mocks.
* **Actor isolation** — a protocol-level `@MainActor` annotation is copied to
  the generated mock class, keeping all mutable test state on the main actor.
* **Interaction validation** — every generated mock with functions exposes
  `recordedCallCounts`. Every property, value-returning function, throwing
  function, and generic handler contributes to `missingStubSelectors` until
  its generated slot is assigned. The setup flag is separate from optional
  storage, so assigning a legitimate `nil` property or optional return marks
  that stub as configured. Run `DIStubValidation.requireAllStubbed` before the
  operation, then pass the same selectors and `recordedCallCounts` to
  `DIInteractionValidation` for strict or recording-only verification.
* **Reset** — every non-empty generated mock exposes
  `innoDIReset(_:)`, `innoDICallHistoryGeneration`, and
  `innoDICallHistorySnapshot`. Use `.calls` to clear call history while
  retaining configured stubs, or `.all` to clear calls and return every stub
  to the missing state. Each call record includes its generation.

## Reset and generation semantics

`innoDIReset(_:)` returns the atomic snapshot of the generation it closes,
then advances the mock to the next generation. This makes a racing call
deterministic: it appears either in the returned old-generation count or in
the new generation, never both. `innoDICallHistorySnapshot` reads the current
generation and every selector count as one aggregate operation.

For `Sendable` mocks, call recording, aggregate snapshots, stub access, and
reset share one `DIConcurrentMockState` critical region. For `@MainActor`
mocks, MainActor serialization supplies the same ordering. Ordinary mocks keep
their documented single-executor contract; callers must not access them from
multiple executors concurrently.

A method is assigned to the generation active when its call record and stub
value are captured. Work performed after that point remains part of the
invocation that already started; reset does not cancel arbitrary user work.
`.calls` preserves every stub and setup flag. `.all` resets the backing value
and setup flag together, so `missingStubSelectors` reports the member again
after reset. Generated helper-name collisions fail closed rather than silently
shadowing a protocol requirement.

## Currently unsupported

The first drop intentionally rejects the following requirements with a
`mock.unsupported-member` warning. InnoDI does not synthesize a partial mock
when any of these appear, because that would generate a broken conformance:

* `static` and `class` requirements (RFC 0001 stage 4).
* Custom global-actor protocols and individually actor-isolated requirements.
  Protocol-level `@MainActor` is supported.
* Function requirement modifiers other than `mutating`, including
  `nonisolated`, `borrowing`, and `consuming`.
* `subscript` requirements (no stable lowering yet).
* `inout` parameters (call-record storage would need a copy policy).
* `rethrows` requirements. Typed `throws(ErrorType)` is supported for
  non-generic requirements; generic typed-throws requirements fail at the
  source attribute instead of emitting a partial conformance.
* Opaque `some` return types.
* Associated types — hand-roll those mocks until the RFC settles on the
  pinning and cross-module resolution path.
* Protocol inheritance other than `AnyObject` and `Sendable`. Attached peer macros cannot
  inspect inherited requirements across files or modules, so InnoDI fails
  closed instead of emitting a mock with a potentially incomplete
  conformance.

If the protocol declares no members at all, the macro emits the
informational `mock.experimental-skeleton` note so adopters can confirm
the macro plugin saw the attribute.

## Diagnostics

| Code | Severity | Cause |
|---|---|---|
| `mock.requires-protocol` | error | `@GenerateMock` was attached to something other than a protocol declaration. |
| `mock.experimental-skeleton` | note | The protocol has no members; the macro emits an empty mock skeleton. |
| `mock.unsupported-member` | warning | One or more protocol members prevent synthesis; the listed names appear in the diagnostic message. |

The DiagnosticsGuide article lists every InnoDI diagnostic with the same
codes and links back to the recovery action.

## When InnoDI's mock isn't enough

`@GenerateMock` deliberately covers only the protocol shapes that InnoDI can
synthesize without leaving the call site ambiguous. When a test case lands on
one of the unsupported requirements above — associated types, `subscript`,
`inout`, `rethrows`, opaque returns, `static`/`class` members — the recommended
path is to reach for an external mocking framework rather than to extend the
generated shape inline.

A few starting points that work well alongside InnoDI:

* Third-party libraries supporting protocol-witness or partial-mock patterns
  are a good fit when the protocol needs `static` requirements,
  custom global actors, or associated-type binding.
* Hand-written conforming structs/classes remain the lightest option for
  small protocols; the macro is meant to remove repetitive boilerplate, not
  to replace one-off conformances.
* For rapidly evolving protocols still under design, prefer a hand-rolled mock
  until the API stabilizes; once the shape settles, swapping in
  `@GenerateMock` is mechanical.

The InnoDI overrides builder accepts any conforming instance, so the choice
of mock library is independent of the container surface. Keep external mocks
in test targets only and pin the version separately from `InnoDI`; the
generated and hand-written paths can coexist without affecting graph
validation.

## Stability

* `@GenerateMock` is an experimental opt-in API. The attribute is
  stable; the *generated* member shape (storage names, helper struct
  names, recorded-call internals) is **not yet stable** and may change
  before GA. Pin the generated names through `Overrides`
  builder slots rather than reaching into the synthesized internals.
* The `bundleWithOverrides:` parameter from RFC 0001 remains reserved for a
  later stage. `Sendable` behavior is inferred from protocol inheritance so
  isolation cannot drift from the production contract.

## See Also

- [RFC 0001 — Macro-driven mock generation](https://github.com/InnoSquadCorp/InnoDI/blob/main/docs/rfcs/0001-macro-mock-generation.md)
- <doc:DiagnosticsGuide>
- <doc:Validation>
