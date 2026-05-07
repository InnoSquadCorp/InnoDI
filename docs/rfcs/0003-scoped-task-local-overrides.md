# RFC 0003 — Scoped TaskLocal overrides

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-05-06
- **Last updated**: 2026-05-06
- **Target release**: TBD — minimum 5.x; can stay deferred while the
  layered swift-dependencies pattern in the README covers most use
  cases.

## Summary

Introduce an opt-in `withScopedOverrides` API on `@DIContainer`-annotated
types. The API runs a closure with a TaskLocal-style override map applied
in front of the container's existing storage so a single call tree can
swap a dependency without rebuilding the container or revalidating its
graph. The shape mirrors `swift-dependencies`'
`withDependencies { $0.x = .mock } operation:` so users with mixed stacks
can reach for the same idiom in either layer.

Not in scope: removing or deprecating the existing
container-level `Overrides` builder or `withOverrides` effect overloads.
Those remain the right tool for app-wide swaps and for situations where
the override outlives one operation.

## Motivation

The May 2026 review flagged that InnoDI's current override surface is
container-shaped: a test that needs to swap one dependency for the
duration of a single function call has to either build a fresh container
or accept a swap that lives for the entire container instance lifetime.
For app-wide swaps that is the right answer; for fine-grained, per-call
overrides it is heavier than the test ergonomics of the surrounding
ecosystem.

Today the README recommends layering with `swift-dependencies` for
exactly this case, and that recommendation should stay valid even after
this RFC ships. The motivation here is to give InnoDI users who do not
already have `swift-dependencies` in their dependency graph a first-class
short-lived override path that participates in InnoDI's validated graph
rather than living outside it.

## Proposed API

```swift
@DIContainer
struct AppContainer {
    @Provide(.input) var clock: any Clock
    @Provide(.shared, factory: { (clock: any Clock) in Logger(clock: clock) }, concrete: true)
    var logger: Logger
}

let container = AppContainer(clock: liveClock) { _ in }

// Sync sugar
let result = container.withScopedOverrides({ overrides in
    overrides.clock = TestClock()
}, operation: {
    runFeatureWorkflow(container)
})

// Async / throws variants mirror the existing withOverrides surface.
try await container.withScopedOverrides({ overrides in
    overrides.clock = TestClock()
}, operation: {
    try await loadAsynchronously(container)
})
```

The override builder type is the existing `Overrides` struct generated
by `@DIContainer`; only the *application* differs. `withScopedOverrides`
uses the same builder convention as `withOverrides`: the first closure
has signature `(inout Overrides) -> Void`, and callers mutate the
generated `Overrides` value in place. A scoped override:

1. Merges the inner `Overrides` on top of the currently-bound outer
   `Overrides` (see Merge semantics below) and binds the result through
   `TaskLocal.withValue` for the duration of the operation closure.
2. Resolves dependencies through that bound value first, falling back
   to the container's stored values when no override is set on the
   relevant field.
3. Restores the previous TaskLocal binding on closure exit (success or
   throw).

## Generated implementation sketch

`@DIContainer` already synthesizes both `init(...)` and the four
`withOverrides(...)` effect overloads. For containers that opt in with
`@DIContainer(scopedOverrides: true)`, this RFC additionally synthesizes:

- A `private static let _scopedOverrides: TaskLocal<Overrides?> = .init(wrappedValue: nil)`
  on each container type.
- Four `withScopedOverrides` overloads (sync / throws / async /
  async throws) parallel to the existing `withOverrides` surface.
- A small adjustment to each accessor's body so it consults
  `Self._scopedOverrides.get()` before reading its `_storage_*` cell.

Non-opt-in containers do not synthesize any of these additions, and
their accessors keep the current shape. For opt-in containers, the
accessor adjustment is paired with the private TaskLocal storage and the
four `withScopedOverrides` overloads above. To keep that generated code
well-typed under strict concurrency, the scoped `Overrides` value must
be `Sendable` (the macro already requires `Sendable` for `.input` and
most factory outputs; the validator will enforce the remaining cases).

## Validation contract

Scoped overrides must not subvert the validated graph:

- Only members that already exist in the container can be overridden.
  The generated `Overrides` builder enforces this at compile time.
- `.shared` overrides replace the cached value for the duration of the
  scope. The macro's existing concurrency contract for `.shared`
  storage continues to hold because the cached value is only read,
  never mutated by the scoped layer.
- `.transient` overrides replace the factory closure for the duration
  of the scope. Concurrent calls inside the scope all see the override.
- Deferred wrappers (`Lazy<T>`, `Provider<T>`) stay non-`Sendable`. A
  scoped override does not change their isolation story, so stored
  members typed as `Lazy<T>` or `Provider<T>` are treated as
  non-overrideable and are excluded from the synthesized `Overrides`
  struct for scoped override purposes.

`@DIContainer(scopedOverrides: true)` additionally synthesizes a
`Sendable` conformance for the generated `Overrides` struct. The macro
validates at expansion time that every overrideable member's stored type
is `Sendable`; if a `.transient` factory closure or a `.shared` value
type cannot satisfy `Sendable` (for example because it captures
non-`Sendable` state), the macro emits a structured diagnostic and
declines to enable scoped overrides on that container. `Lazy<T>` and
`Provider<T>` members are skipped for this Sendable check rather than
rejecting the container; the macro emits a structured informational or
warning diagnostic naming the omitted members and explaining that the
deferred wrapper surface is not scoped-overrideable. Containers that do
not opt in keep their current non-`Sendable` `Overrides` shape.

The graph CLI gains no new node kinds; scoped overrides are an
operation-time concept, not a graph-time concept.

## Merge semantics

`TaskLocal.withValue` is binding-overshadowing, not merging. A naive
implementation that simply binds the inner `Overrides` would erase
every override the outer scope set unless the inner caller copied each
field forward. That regression is non-obvious and surfaces only in
nested-scope tests, so the RFC requires explicit merge semantics.

When `withScopedOverrides` enters a nested scope, the macro-synthesized
implementation merges the inner overrides on top of the outer-effective
overrides before binding the TaskLocal. The macro emits a
`merge(into:)` helper on `Overrides` that copies non-`nil` fields from
the inner builder into a copy of the currently-bound outer value;
fields the inner caller did not touch keep the outer override in scope.
The cost is one struct copy per scope entry, which is acceptable given
that scoped overrides are an operation-time tool, not a hot-path
abstraction.

```swift
container.withScopedOverrides({ outer in outer.clock = TestClock.frozen }) {
    container.withScopedOverrides({ inner in inner.logger = NoopLogger() }) {
        // Both overrides apply; inner.clock falls through to outer's TestClock.frozen.
    }
}
```

`Overrides.merge(into:)` is `Sendable`-respecting: it only ever copies
already-`Sendable` values (see `Sendable` conformance above) and never
captures non-`Sendable` closures.

## Comparison with swift-dependencies

| Concern | InnoDI scoped overrides | swift-dependencies |
|---|---|---|
| Override surface | Same `Overrides` builder as the container | `DependencyKey` per-feature |
| Validation | App-graph macro + build plugin | None at the dependency layer |
| Override application | Per-call via TaskLocal stack | Per-call via TaskLocal binding |
| Composition | Container can host multiple scopes | One global registry |
| Mixed use | Coexists; users can pick per call site | Coexists |

The README continues to recommend layering both libraries; the new API
just removes the *force* to add `swift-dependencies` for users who only
need a small TaskLocal seam.

## Alternatives considered

1. **Do nothing.** README guidance to layer with `swift-dependencies`
   already addresses the use case. Reasonable default until adoption
   demand becomes clear.
2. **Reuse the existing `withOverrides` surface but document that the
   container is throwaway.** Forces a rebuild per call, defeats the
   ergonomics goal, and re-runs DAG validation more than necessary.
3. **A separate `ScopedOverrides` type distinct from `Overrides`.**
   Reviewers would have to learn two shapes; the proposed API reuses
   the same builder so reviewers can read either site identically.

## Open questions

- Should `withScopedOverrides` be available on `@SubContainer` members
  too, or only on the root container? Sub-container scoping doubles the
  TaskLocal surface and may need its own RFC.
- Does the macro need a per-member opt-out for callers who want a
  member to remain immutable for the duration of a scope? The current
  proposal makes every member overrideable; an opt-out would mirror
  the existing `Overrides` builder shape exactly.
- ~~Strict-concurrency: do we need to mark the per-container TaskLocal
  with `@MainActor` when the container itself is `mainActor: true`?~~
  Resolved (2026-05-06): the per-container TaskLocal stays `nonisolated`
  regardless of `mainActor: true`. The wrapped `Overrides` value is
  `Sendable` (see Validation contract), so reading it from any
  isolation domain is safe. `@MainActor` containers continue to read
  scoped overrides without crossing isolation boundaries; the macro
  emits the TaskLocal storage as a plain `static let` and the access
  helper is `nonisolated`.

## Migration

This is purely additive. Existing containers that do not opt in continue
to compile and run identically, with the same generated shape. The
`withScopedOverrides` surface appears only on containers that explicitly
request `@DIContainer(scopedOverrides: true)`. No deprecations; the RFC
explicitly keeps `withOverrides` as the canonical app-wide swap.

## Implementation phases

1. **Phase 1 (this RFC, post-approval)** — generate the TaskLocal,
   `withScopedOverrides` overloads, and accessor adjustments behind a
   feature flag (`@DIContainer(scopedOverrides: true)`). Land in 5.0
   experimental.
2. **Phase 2** — promote to the default after one minor release of
   feedback. Update the README's swift-dependencies guidance to call
   out scoped overrides as the in-house alternative.
3. **Phase 3** — extend to `@SubContainer` members, gated by a separate
   RFC if the open questions need their own deliberation.

## GA Criteria

This RFC is currently **Draft**. The maintainers do not consider scoped
TaskLocal overrides eligible for a `skeleton` implementation phase until the
RFC moves to `Accepted` with the open questions above answered. Once a
skeleton lands, the same five gates documented in
[ROADMAP — GA criteria for experimental macros](../../ROADMAP.md#ga-criteria-for-experimental-macros)
apply, with the following surface-specific specializations:

1. **Open questions resolved.** Every bullet in `## Open questions` either
   has a written answer in this RFC or is explicitly marked
   `Out-of-scope for GA` with a follow-up RFC reference.
2. **Snapshot coverage.** The merge-semantics matrix from `## Merge
   semantics` is covered by macro snapshot tests, including the cases that
   currently lack runtime tests.
3. **Strict-concurrency clean.** TaskLocal-backed overrides compile and
   resolve under
   `-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`,
   including across the actor boundaries that this RFC documents as
   supported.
4. **Adopter signal.** At least two real-world adopters (internal or
   external) have reported usage of scoped overrides without merge-semantic
   surprises, and the layered swift-dependencies pattern documented in the
   README still works for the cases this surface intentionally does not
   cover.
5. **Promotion PR.** Same 7-day cooldown promotion PR pattern as the macro
   surfaces — flips the docstring, the ROADMAP entry, and bumps the
   relevant minor in `RELEASING.md`.

If the macro/runtime work for this surface ever ships behind a feature flag
or package trait, document the flag/trait and its removal plan inline above
this section before the next minor release.

## See Also

- [README — Layered InnoDI + swift-dependencies pattern](../../README.md)
- [RFC 0001 — Macro-driven mock generation](0001-macro-mock-generation.md)
- [RFC 0002 — SubContainer wiring simplification](0002-subcontainer-wiring-simplification.md)
