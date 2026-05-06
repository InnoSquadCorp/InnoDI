# Auto Mock Generation

`@GenerateMock` (RFC 0001) synthesizes a call-recording mock peer for a
protocol so tests can plug into the existing `Overrides` builder without
hand-writing the mock body. The attribute is shipping in 4.x as
**experimental**; the generated shape may evolve before 5.0 GA.

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
conforms to the protocol and `@unchecked Sendable`. Tests instantiate the mock,
populate the stubs, and read recorded calls back:

```swift
let mock = UserServiceMock()
mock.prefix = "test"
mock.fetchResult = .success("hello")

let value = try await mock.fetch(id: "42")
#expect(value == "hello")
#expect(mock.fetchCalls.last?.id == "42")

mock.reset()
#expect(mock.resetCalls.count == 1)
```

## Generated shape

For each supported protocol member the macro emits the following:

* **`var prop: T { get set }`** — `var prop: T!` (implicit-unwrapped
  optional storage; populate before reading).
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
  set.
* **`func name(args) async throws -> T`** — combines the two cases.
* **Overloaded functions** — helper names include selector labels and parameter
  type stems so `fetch(id:)` and `fetch(page:)` do not collide.
* **Generic functions** — the generated method preserves generic clauses and
  stores an erased `([Any]) -> Any` handler, with matching `async` / `throws`
  effects when needed. Tests cast through the generic return type at the call
  boundary.
* **`mutating` requirements** — supported through the generated `final class`
  mock; the synthesized method does not need to be marked `mutating`.
* **Escaping closure arguments** — recorded with property-safe function types
  (`@escaping` / `@autoclosure` are removed from the call-record field while
  the conforming method keeps the original parameter spelling).

## Currently unsupported

The first drop intentionally rejects the following requirements with a
`mock.unsupported-member` warning. InnoDI does not synthesize a partial mock
when any of these appear, because that would generate a broken conformance:

* `static` and `class` requirements (RFC 0001 stage 4).
* `subscript` requirements (no stable lowering yet).
* `inout` parameters (call-record storage would need a copy policy).
* `rethrows` and typed `throws(ErrorType)` requirements.
* Opaque `some` return types.
* Associated types — hand-roll those mocks until the RFC settles on the
  pinning and cross-module resolution path.

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

## Stability

* `@GenerateMock` is an experimental opt-in API. The attribute is
  stable; the *generated* member shape (storage names, helper struct
  names, recorded-call internals) is **not yet stable** and may change
  between 4.x releases. Pin the generated names through `Overrides`
  builder slots rather than reaching into the synthesized internals.
* The `bundleWithOverrides:` and `sendable: .strict` parameters from RFC
  0001 are reserved for the next stage. Treat the current macro as the
  protocol-mock path only.

## See Also

- [RFC 0001 — Macro-driven mock generation](../../docs/rfcs/0001-macro-mock-generation.md)
- <doc:DiagnosticsGuide>
- <doc:Validation>
