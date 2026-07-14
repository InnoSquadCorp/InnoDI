# RFC 0004 — API surface simplification

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-05-08
- **Last updated**: 2026-07-14
- **Target release**: Future major release; not part of the 5.0 hardening scope
- **Superseded in part by**: RFC 0005 (`concrete:` implementation plan)

> **July 2026 status correction:** the 4.3/4.4 inference runway described in
> this RFC did not ship. InnoDI 4.3.0 shipped `@SubContainer` feature-root
> helpers instead, which also completed candidate 2 below in a different API
> shape. RFC 0005 now defines the accepted 5.0 contract-hardening train,
> removes `concrete:` by using the declared property type as the single source
> of truth, and defers the remaining macro-consolidation candidates. The text
> below is retained as design history, not as the active 5.0 implementation
> plan.

## Summary

The 2026-05 whole-repository review flagged API surface complexity as an
onboarding obstacle for new adopters. This RFC recorded an exploratory
breaking-change track. It is no longer the active 5.0 plan; RFC 0005 limits
5.0 to contract hardening and a smaller set of proven surface removals.

Two concrete simplifications are in scope:

1. **`concrete:` parameter removal.** The `@Provide(... concrete: true)` flag
   exists today as a workaround for SwiftSyntax's lack of resolved type
   information at macro-expansion time. The macro should infer concrete vs.
   existential storage from the declared property type and the factory return
   type whenever both agree, and only require an explicit opt-in when the two
   sides genuinely disagree.
2. **Macro consolidation.** InnoDI exposes nine attached macros across the
   `InnoDI` and `InnoDISwiftUI` runtime targets (`@DIContainer`, `@Provide`,
   `@SubContainer`, `@DIComponent`, `@DIHierarchyRoot`, `@GenerateMock`,
   `@DIEnvironmentBridge`, `@DIFeatureRoot`, `#PreviewWithContainer`).
   Several of these are orthogonal in user intent but expressed as separate
   declarations. The plan evaluates which combinations can fold into a single
   macro without losing diagnostic precision or generated-code clarity.

Both changes were originally proposed for the same breaking train. They are no
longer coupled: RFC 0005 supersedes the inference/token design and the
remaining macro-consolidation candidates require separate acceptance before a
future major release.

## Motivation

### Where the complexity comes from

The current 4.x macro signature requires every adopter to internalise:

- `concrete: true` on every concrete-storage `@Provide` even when the
  property type is already a concrete struct/class.
- Three wiring forms on `@SubContainer` (`with:`, `bindings:`, implicit) plus
  the rule that `with:` and `bindings:` are mutually exclusive.
- `@DIComponent` on the child, `@DIHierarchyRoot` on the root, and the
  documented contract that hierarchy validation only activates when at least
  one root marker is present.
- `@DIEnvironmentBridge` and `@DIFeatureRoot` as separate macros even though
  both annotate the same root container property in practice.
- `@GenerateMock` as an experimental peer macro whose output shape is not
  SemVer-frozen until it independently passes the GA criteria.

The 4.2 release ships the wiring-simplification work from RFC 0002 and the
escape-hatch reporting that landed during the 4.1.x hardening pass; the
remaining surface burden is now concentrated in `concrete:` and the
macro-count itself.

### Why now

- The 4.2.0 release closes the long-running `withNames:` migration window
  and freezes `@SubContainer`'s wiring contract. With wiring stable, the
  next minor cycle can absorb a different shape change without compounding
  user migrations.
- At proposal time, SwiftSyntax 602+ exposed enough property-type and
  attribute-argument syntax to explore heuristic `concrete:` inference
  without a full type-checker. The current package uses a newer SwiftSyntax
  line and the accepted 5.0 design does not depend on factory-return inference.
- `@GenerateMock` promotion is now independent of the 5.0 train and occurs
  only after its published GA criteria pass.

### Non-goals

- This RFC does **not** propose a runtime registration API or an
  `@Injected` property wrapper. Those remain explicitly out-of-scope per the
  README's "When to choose InnoDI" framing.
- This RFC does **not** propose merging `@DIContainer` and `@Provide`. The
  two are orthogonal in user intent and well-understood.
- This RFC does **not** propose changing `Lazy<T>` / `Provider<T>` shape.
  Their non-`Sendable` handle design stays.
- Build-plugin behaviour, lock-safety semantics, and graph-CLI rendering are
  out of scope.

## Part A — `concrete:` inference

### Today

```swift
@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String

    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL], concrete: true)
    var apiClient: APIClient

    @Provide(.shared, factory: { (client: APIClient) in
        Logger(client: client)
    }, concrete: true)
    var logger: Logger
}
```

Both `apiClient` and `logger` are forced to spell `concrete: true`. The
property type (`APIClient`, `Logger`) and the factory's return type already
agree; the macro emits the flag-required diagnostic only because it cannot
prove that agreement from syntax alone.

### Proposed shape

```swift
@DIContainer
struct AppContainer {
    @Provide(.input) var baseURL: String

    // No concrete: flag. The macro reads `APIClient` from the property type
    // and the `APIClient.self` argument; both agree, so it picks concrete
    // storage automatically.
    @Provide(.shared, APIClient.self, with: [\AppContainer.baseURL])
    var apiClient: APIClient

    // No concrete: flag. The factory return type is `Logger`, the property
    // type is `Logger`; concrete is the only consistent choice.
    @Provide(.shared, factory: { (client: APIClient) in
        Logger(client: client)
    })
    var logger: Logger

    // Existential property type. The macro keeps existential storage and
    // does not require an opt-in.
    @Provide(.shared, factory: APIClient(baseURL: ""))
    var apiClientProtocol: any APIClientProtocol
}
```

### Inference rules

The macro picks concrete storage when **all** of the following hold:

1. The declared property type is a `TypeSyntax` whose canonical spelling is
   not `any P`, `some P`, or a `(P) -> Q` function type.
2. The `@Provide` argument set contains a `Type.self` argument whose written
   identifier matches the property type's canonical spelling, **or** the
   factory closure's declared return type matches the property type's
   spelling.
3. No other `@Provide` argument forces existential storage (none currently
   do, but the rule keeps the inference monotonic against future arguments).

If those conditions are not met, the macro keeps the current existential
storage shape. Authors who genuinely want concrete storage for an
existential property type — a rare case — opt in with the new
`@Provide(.shared, .concrete)` token form, replacing the boolean flag.

### Failure modes

| Site | Macro behaviour |
|---|---|
| Property type and factory return type disagree | Diagnostic `provide.concrete-inference-conflict` with a fix-it offering both directions. |
| Property type is `any P`, factory returns concrete `P` impl | Existential storage (current behaviour); no diagnostic. |
| Property type is concrete `P`, factory returns `any P` | Diagnostic `provide.concrete-inference-conflict` (the cast is silent today, which has caused production confusion). |
| Property type spelled with module qualifier (`Foo.APIClient`) | Inference compares trimmed canonical text; module-qualified spellings match unqualified factory returns within the same module. |

### Historical migration runway (not shipped)

- **4.3.0** (target): introduce inference behind `@DIContainer(inferConcrete: true)`
  opt-in. Existing `concrete: true` sites continue to compile unchanged. New
  sites can drop the flag inside opt-in containers and verify locally.
- **4.4.0** (target): emit `provide.concrete-flag-deprecated` warning with a
  fix-it that removes the flag at sites where inference would pick the same
  storage shape. The opt-in flag flips to opt-out (`inferConcrete: false`)
  for last-mile escape.
- **5.0.0**: remove the `concrete:` parameter and the `inferConcrete:`
  container flag. Inference is the only behaviour. The new
  `@Provide(.shared, .concrete)` token covers the residual opt-in case.

A codemod ships in `Tools/codemod-drop-concrete-flag.swift` and runs as a
single `swift Tools/codemod-drop-concrete-flag.swift <package-path>`. The
codemod is conservative: it only deletes the flag at sites where inference
would land on the same storage shape, leaving `provide.concrete-inference-conflict`
sites untouched for human review.

## Part B — Macro consolidation candidates

This part is exploratory. Each candidate has a separate go/no-go decision
that the maintainer team will make during the 4.3 cycle based on
prototyping outcomes.

### Candidate 1: fold `@DIComponent` into `@DIContainer(mountable:)`

**Today.** A cross-module mountable container is annotated with both:

```swift
@DIComponent
@DIContainer
public struct FeatureContainer { ... }
```

`@DIComponent` lifts the container's `.input` members into a generated
`<Container>Dependencies` contract and synthesises the mounting initializer.
The two macros are paired in 100 % of supported cases.

**Proposed.**

```swift
@DIContainer(mountable: true)
public struct FeatureContainer { ... }
```

The `mountable:` parameter triggers the dependencies-contract generation
that `@DIComponent` performs today. Generated symbol names stay identical
so build-support hierarchy validation does not change.

**Trade-offs.**
- Pro: removes one macro, removes the stack-order question.
- Con: `@DIContainer` already takes three parameters; adding a fourth
  pushes call sites toward the signature limit where readability degrades.
- Con: codemod needs to migrate two macros into one parameter; non-trivial.

**Open question:** does `mountable:` belong on `@DIContainer` or as a
separate marker that's clearly visual at the type's declaration line?

### Candidate 2: fold `@DIFeatureRoot` into `@SubContainer(rootView:)`

**Today.**

```swift
@SubContainer(scope: .shared, with: [\.config])
@DIFeatureRoot(DashboardRootView.self)
@DIFeatureRoot(DashboardShellView.self, as: "dashboardShell")
var dashboard: DashboardContainer
```

The stacked peer-macro shape was the source of the `withNames:` escape
hatch that RFC 0002 just removed. Even after the simplification, two macros
co-occur whenever a SwiftUI parent wants typed root-view helpers.

**Proposed.**

```swift
@SubContainer(scope: .shared, with: [\.config], rootViews: [
    DashboardRootView.self,
    (DashboardShellView.self, as: "dashboardShell"),
])
var dashboard: DashboardContainer
```

The `rootViews:` argument generates the same `dashboardRootView()` and
`dashboardShellRootView()` helpers `@DIFeatureRoot` produces today.

**Trade-offs.**
- Pro: removes the stacked peer-macro shape entirely. RFC 0002's
  motivation (peer-macro key-path expansion fragility) disappears.
- Con: tuple-with-label syntax inside an attribute argument is ergonomic
  on paper but historically brittle in macro parsing. A prototype must
  validate the syntax before the candidate is accepted.

**Open question:** can `rootViews:` accept arbitrary literal arrays the
macro can read, the way `with:` does today?

### Candidate 3: implicit `@DIHierarchyRoot`

**Today.** A workspace activates rooted hierarchy validation by annotating
at least one container with `@DIHierarchyRoot`. The marker has no other
effect.

**Proposed.** When the workspace contains at least one `@DIComponent`
(or `@DIContainer(mountable: true)` after candidate 1), the build-support
hierarchy validator activates automatically. The `@DIHierarchyRoot` marker
moves from required to optional, and is fully removed in 5.1 if no surface
need emerges.

**Trade-offs.**
- Pro: removes one macro from the surface count.
- Con: changes the validator's activation condition. Workspaces that
  previously had `@DIComponent` annotations but no root would suddenly see
  hierarchy diagnostics they didn't see before. The 4.x deprecation cycle
  must surface this with a single `hierarchy.implicit-root-activated`
  warning the first time the auto-activation fires.

**Open question:** is there a use case for `@DIComponent` containers in a
workspace that should *not* run hierarchy validation? If yes, an explicit
opt-out flag is needed.

### Candidate 4: `.innodi(container)` without `@DIEnvironmentBridge`

**Today.**

```swift
@DIEnvironmentBridge([
    (member: "service", environment: \EnvironmentValues.service),
    ...
])
@DIContainer struct AppContainer { ... }
```

`@DIEnvironmentBridge` synthesises a `ViewModifier` from the explicit
member-to-environment-keypath mapping.

**Proposed.** Move the mapping out of the macro and into a protocol
conformance the user writes once:

```swift
extension AppContainer: DIEnvironmentBridging {
    static let innodiEnvironmentBridge = DIEnvironmentBridge<AppContainer>(
        members: [
            \.service .. \EnvironmentValues.service,
            \.logger  .. \EnvironmentValues.logger,
        ]
    )
}

ContentView()
    .innodi(container)
```

The `.innodi(container)` view modifier reads the static bridge and applies
it. No macro is required; the operator-spelled tuple gives compile-time
type checking on both sides.

**Trade-offs.**
- Pro: removes another macro from the surface count.
- Con: the static-let mapping is more verbose than the macro for large
  containers; the surface-count saving may not outweigh the per-site cost.
- Con: requires a custom operator (`..`) or a typed builder; both add
  cognitive load.

**Open question:** is the macro shape genuinely a problem for adopters,
or is the surface-count concern overstated for the SwiftUI bridge case?
The decision should be driven by adopter feedback collected during the
4.2.x cycle.

## Historical migration & deprecation runway

### Proposed 4.x window (not shipped)

- 4.3.0: `inferConcrete: true` opt-in on `@DIContainer`. Macro consolidation
  candidates remain in prototype branches; no public surface change.
- 4.4.0: `provide.concrete-flag-deprecated` warning at every site where
  inference would pick the same shape. `concrete:` is still accepted.
  `Tools/codemod-drop-concrete-flag.swift` ships.
- 4.4.0: prototype branches for each macro consolidation candidate are
  reviewed against measurable adopter signal. Each candidate either
  promotes to a Draft RFC of its own or is rejected with a written reason.

### Originally proposed 5.0.0 shape (superseded)

- `concrete:` parameter removed.
- `@Provide(.shared, .concrete)` token form added for residual opt-in.
- Each accepted macro consolidation candidate ships with its own breaking
  notice and codemod entry in `Tools/codemod-*`.
- `MigrationGuide.md` adds a 4.x → 5.0 chapter that walks through every
  surface change with before/after snippets.

### 5.x follow-ups (out of scope here, tracked separately)

- 5.1: remove redundant deprecation surfaces if no friction surfaces post-5.0.
- 5.x: revisit per-call override surface (RFC 0003) once the simplified core
  macros stabilise.

## Open questions

- **Inference precision.** What fraction of real-world `concrete: true`
  sites does the proposed inference rule cover? The 4.3 cycle should run
  the rule against `Examples/`, the synthetic consumer benchmark, and at
  least two internal adopter codebases before the warning lands in 4.4.
- **Macro signature ceiling.** Candidates 1 and 2 both add parameters to
  existing macros. The team should agree on a maximum parameter count per
  macro (proposed: five) before each candidate's prototype merges.
- **Codemod tooling.** Should InnoDI ship a single `swift package`-level
  codemod entrypoint (`swift run InnoDI-Codemod`), or per-change scripts?
  The decision affects 4.4's release surface.
- **Adopter signal collection.** The 4.2.x cycle should bundle a short
  feedback form in the workflow step summary asking adopters which 5.0
  candidate they would prioritise. The RFC moves from Draft to Accepted
  only after at least one cycle of that signal is collected.

## Implementation status

Not started. The `concrete:` implementation plan was superseded by RFC 0005,
candidate 2 shipped in 4.3.0 as `@SubContainer(featureRoot:)` and
`featureRoots:`, and the other consolidation candidates remain unaccepted.

## Related work

- [RFC 0001](0001-macro-mock-generation.md) — `@GenerateMock` remains
  experimental until its independent GA criteria pass.
- [RFC 0002](0002-subcontainer-wiring-simplification.md) — `@SubContainer`
  wiring stabilised in 4.2.0; this RFC continues the simplification arc.
- [RFC 0003](0003-scoped-task-local-overrides.md) — scoped task-local
  overrides; orthogonal to this RFC and revisited after 5.0 ships.
