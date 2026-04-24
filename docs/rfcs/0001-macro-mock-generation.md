# RFC 0001 — Macro-driven mock generation

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-04-24
- **Target release**: TBD (post 4.x, likely 5.0)

## Summary

Attach a new `@GenerateMock` macro to a Swift protocol (and optionally to
a `@DIContainer` type) to have InnoDI synthesize a compile-time mock
implementation. The generated type is `Sendable` where possible, captures
every call for assertion, and plugs into the existing `Overrides`
builder so tests can replace a production binding with its mock in a
single line.

Not in scope for this RFC: runtime mocking (swizzling, proxy objects),
partial mocks that fall back to the real implementation, or anything that
requires reflection.

## Motivation

InnoDI's current `Overrides` builder is excellent at swapping an
instance of a production type for a test instance, but writing the
test instance is still pure boilerplate. Every protocol the user
wants to mock requires a hand-written class that:

- conforms to the protocol,
- records call arguments into an array,
- exposes stubs for return values,
- handles `async` / `throws` / `rethrows` permutations,
- needs to stay in sync when the protocol evolves.

For large feature containers this quickly becomes a hundreds-of-lines-
per-feature maintenance burden. Unit tests in the Examples directory
today already repeat "hand-rolled mock" patterns three or four times.

SafeDI solves this with `@Instantiable(generateMock: true)`. Stitch
and Crocodil do not offer it. We believe InnoDI should match or exceed
SafeDI's developer experience here while keeping our graph-centric
feel and our Overrides-builder-first testing story.

## Proposed API

```swift
@GenerateMock
protocol UserService {
    func fetch(id: String) async throws -> User
    func save(_ user: User) async
}

// Macro expansion produces:

final class UserServiceMock: UserService, @unchecked Sendable {
    struct FetchCall: Equatable { let id: String }
    struct SaveCall: Equatable { let user: User }

    private(set) var fetchCalls: [FetchCall] = []
    private(set) var saveCalls: [SaveCall] = []

    var fetchResult: Result<User, Error> = .failure(MockNotStubbed(selector: "fetch(id:)"))
    var saveHandler: ((User) async -> Void)? = nil

    func fetch(id: String) async throws -> User {
        fetchCalls.append(.init(id: id))
        return try fetchResult.get()
    }

    func save(_ user: User) async {
        saveCalls.append(.init(user: user))
        await (saveHandler?(user) ?? ())
    }
}

struct MockNotStubbed: Error { let selector: String }
```

### Options

- `@GenerateMock(bundleWithOverrides: ContainerName.self)` — install the
  mock into the container's `Overrides` builder automatically so
  `withOverrides { $0.userService = UserServiceMock() }` works without
  the user writing anything further.
- `@GenerateMock(sendable: .strict)` — drop `@unchecked Sendable` in
  favor of a fully-`Sendable` implementation (requires all arguments and
  return types to be `Sendable`).

### Relationship with Overrides

InnoDI's `Overrides` builder is the *consumption* surface for mocks.
`@GenerateMock` is a *production* convenience. The generated mock must
be assignable to any protocol-typed `@Provide(.shared, factory: ...)`
or `@Provide(.transient, factory: ...)` binding without adjustment.
We will add a `@InnoDIMockBundle` macro to container types so every
mock associated with that container installs into the overrides
builder by default; teams can opt out per-test when they want
mixed real/mock graphs.

## Differentiation vs SafeDI

| Feature                                  | SafeDI | InnoDI (proposed) |
|-----------------------------------------|--------|-------------------|
| Protocol mock without a DI container     | ✗      | ✅                |
| Async / throws first-class               | Partial| ✅                |
| Typed throws (`throws(E)`) in signatures | ✗      | ✅ (Swift 6)      |
| Swift Testing helpers for call checks    | ✗      | ✅                |
| Container-bundled mock installation      | ✅     | ✅                |
| Runtime-mock fallback                    | ✗      | ✗                 |

## Open questions

- **Generic protocols**: do we synthesize a generic mock class, or
  require the user to specify the concrete instantiation on the macro?
  Leaning toward "generic mock" — it preserves the callability of the
  protocol and matches what users expect.
- **Associated types**: Swift macros can read associatedtype
  declarations but not resolve their constraints across modules. We
  may need to require the user to pin them via
  `@GenerateMock(associatedTypes: ["Token": AuthToken.self])`.
- **Actor protocols**: how should we model protocols with actor
  isolation inherited from `@globalActor`? Likely a separate mode
  (`.actor` vs `.sendableStruct`).
- **Mutation tracking**: call records grow unbounded per test. Do we
  need a `reset()` helper, or leave lifecycle to the test author?
- **Snapshot of call args**: some types are hard to `Equatable`. A
  fallback "opaque" call record that stores `Any` may be useful, but
  loses `#expect` comparison ergonomics.

## Alternatives considered

1. **External tool (Mockolo / Sourcery)** — works today but requires a
   separate code-generation step outside SPM. InnoDI's selling point is
   first-party macro tooling; shipping a second generator contradicts
   that.
2. **Runtime reflection** — Swift's reflection is deliberately limited
   and cannot observe protocol method signatures, so this is not a
   viable path.
3. **Hand-rolled protocol witness structs** — what we have today.
   Works but is the maintenance burden we're trying to eliminate.

## Rollout plan

1. Ship `@GenerateMock` as an experimental macro behind
   `.enableExperimentalFeature("InnoDIMockGeneration")` for one minor
   release so we can evolve the generated shape without breaking users.
2. Collect feedback from Examples and a handful of adopter repos on
   the open questions above.
3. Promote to stable with a dedicated RFC revision that documents the
   final API + migration guidance.

## Out of scope

- Mocking `@SubContainer` children (the plan is to leverage the
  existing child-Overrides path).
- Mocking concrete types (final classes / structs) — protocols are the
  testable abstraction boundary InnoDI already encourages.
- Auto-generating XCTest / swift-testing helpers beyond the minimal
  `#expect(mock.fetchCalls.last?.id == "42")` ergonomics.

## Open-source etiquette

RFC 0001 is the maintainers' initial sketch; public comments are welcome
via GitHub discussions. We will tag the RFC `Accepted` only after the
open questions above receive written answers and at least one example
project compiles against the generated code end-to-end.
