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
by `@DIContainer`; only the *application* differs. A scoped override:

1. Pushes the override map onto a per-container TaskLocal stack at the
   start of the operation closure.
2. Resolves dependencies through that stack first, falling back to the
   container's stored values when no override is set.
3. Pops the stack on closure exit (success or throw).

## Generated implementation sketch

`@DIContainer` already synthesizes both `init(...)` and the four
`withOverrides(...)` effect overloads. This RFC adds:

- A `private static let _scopedOverrides: TaskLocal<Overrides?> = .init(wrappedValue: nil)`
  on each container type.
- Four `withScopedOverrides` overloads (sync / throws / async /
  async throws) parallel to the existing `withOverrides` surface.
- A small adjustment to each accessor's body so it consults
  `Self._scopedOverrides.get()` before reading its `_storage_*` cell.

The accessor change is the only generated-code shape that changes for
existing call sites. To keep the generated code well-typed under strict
concurrency, every accessor that participates in the scoped path must
have a `Sendable` storage type (the macro already requires `Sendable`
for `.input` and most factory outputs; the validator will enforce the
remaining cases).

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
  scoped override does not change their isolation story.

The graph CLI gains no new node kinds; scoped overrides are an
operation-time concept, not a graph-time concept.

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
- Strict-concurrency: do we need to mark the per-container TaskLocal
  with `@MainActor` when the container itself is `mainActor: true`?
  Current sketch keeps it `nonisolated` and relies on the wrapped
  value's own `Sendable` story.

## Migration

This is purely additive. Existing containers continue to compile and
run identically; the `withScopedOverrides` surface only appears for
users who explicitly call it. No deprecations; the RFC explicitly
keeps `withOverrides` as the canonical app-wide swap.

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

## See Also

- [README — Layered InnoDI + swift-dependencies pattern](../../README.md)
- [RFC 0001 — Macro-driven mock generation](0001-macro-mock-generation.md)
- [RFC 0002 — SubContainer wiring simplification](0002-subcontainer-wiring-simplification.md)
