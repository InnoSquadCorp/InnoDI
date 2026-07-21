# RFC 0001 — Macro-driven mock generation

- **Status**: Accepted (experimental); available on `main` as opt-in
- **Authors**: InnoDI maintainers
- **Created**: 2026-04-24
- **Last updated**: 2026-07-17
- **Target release**: Experimental until the published GA criteria
  pass (not a 5.0 blocker)

## Initial answers to open questions

| Question | Answer |
|---|---|
| Generic protocols | Synthesize a generic mock class; preserves callability and matches user expectations. |
| Generic methods | Supported in the experimental implementation with erased handler closures and preserved generic clauses. |
| Associated types | Require explicit pinning via `@GenerateMock(associatedTypes: ...)` until cross-module resolution lands in SwiftSyntax. |
| Actor protocols | Out-of-scope for the initial drop. Track in a follow-up RFC; users can manually implement actor mocks for now. |
| Mutation tracking | Provide an opt-in `reset()` helper; default behavior records all calls without bound. |
| Snapshot of call args | Generated `Call` structs conform to `Equatable` when all parameters do, otherwise fall back to `Any`-typed record. |

## Summary

Attach a new `@GenerateMock` macro to a Swift protocol (and optionally to
a `@DIContainer` type) to have InnoDI synthesize a compile-time mock
implementation. The generated type captures every call for assertion and plugs
into the existing `Overrides` builder so tests can replace a production binding
with its mock in a single line.

In the current experimental implementation, generated mocks are intentionally
not `Sendable` by default because call arrays, result slots, and handlers are
plain mutable state. Lock-backed strict-sendable mocks remain a follow-up
option.

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

final class UserServiceMock: UserService {
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
- `@GenerateMock(sendable: .strict)` — emit a fully-`Sendable` implementation
  backed by synchronized state (requires all arguments and return types to be
  `Sendable`).

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

1. Ship `@GenerateMock` as an experimental library feature for one minor
   release so we can evolve the generated shape without breaking users.
   The public attribute ships without a trait gate, but generated helper names
   stay explicitly non-frozen until a dedicated GA promotion.
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

## Implementation Status

Phase: **stage-2** (see [ROADMAP.md](../../ROADMAP.md#pipeline-phases) for
phase definitions). This section is updated in the same PR that lands a
status-changing piece of work, so it can serve as the rolling truth between
RFC revisions.

- [x] RFC accepted (experimental, opt-in)
- [x] Macro skeleton (`@GenerateMock` attribute + diagnostic for non-protocol
      attachment)
- [x] Top-level protocol synthesis with overload-qualified helper names
- [x] Generic method requirements via erased handler closures
- [x] Inherited protocols fail closed until inherited-requirement resolution
      is available (`AnyObject` class bounds remain supported)
- [x] Snapshot tests for the supported call shapes
- [ ] Async / `throws` method shapes covered by snapshots end-to-end
- [ ] Associated-type protocols (per RFC `Initial answers to open questions`,
      with `@GenerateMock(associatedTypes: ...)` syntax)
- [ ] Actor-isolated protocols — currently *Out-of-scope for GA* and tracked
      separately
- [ ] `bundleWithOverrides:` integration with the `Overrides` builder
- [ ] At least two adopter reports captured (see GA criteria #4)
- [ ] Strict-concurrency-clean snapshots across the supported shape matrix
- [ ] Promotion PR opened with a 7-day cooldown

When a checkbox flips, link the PR or issue that flipped it inline with the
item.

## GA Criteria

`@GenerateMock` graduates to GA only when **all** of the following hold on
`main`. These mirror the macro promotion gates documented in
[ROADMAP.md](../../ROADMAP.md#ga-criteria-for-experimental-macros) and exist
in the RFC so that a single commit reviewer can verify them without
context-hopping.

1. **RFC open questions resolved** — the `## Open questions` section is
   empty, or every remaining bullet is explicitly marked
   `Out-of-scope for GA` with a follow-up RFC reference.
2. **Snapshot coverage** — every in-scope variant (sync, async, throws,
   generic, overloaded, associated-type-bound) is covered by an
   `assertMacroExpansion*` snapshot test. Snapshot diffs from the previous
   minor are reviewed and intentional.
3. **Strict-concurrency clean** — generated mocks compile under
   `-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` in
   the PR gate without warnings.
4. **Adopter signal** — at least two real-world adopters (internal or
   external) have reported usage on the `stage-2` drop without naming-shape
   blockers. References are captured in this section.
5. **Promotion PR** — a maintainer opens a PR that flips the docstring from
   "Experimental" to the stable description, removes the experimental marker
   from the ROADMAP table, and bumps the relevant minor in `RELEASING.md`.
   The PR sits open for a 7-day cooldown so existing adopters can object.
