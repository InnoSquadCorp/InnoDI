# Macro-first follow-up: close practical owned-container gaps

This work follows the immutable first checkpoint, not a replacement of its
measurements or 7.7 / CS 8.0 / DX 7.4 assessment. The starting checkout is main
`8177f8d7c3b74822b181b1616d67fe1e2e6482a7` with that checkpoint patch applied.
Main's intervening 16-file CI/documentation delta is disjoint from the 144-file
checkpoint. The previous ZIP and manifest remain untouched.

## 1. Reuse test overrides when constructing an owner

Today callers must unpack an existing `Container.Overrides` into named arguments.
Add one required, nonescaping trailing-closure convenience, only under
`generateOwned: true`:

```swift
// Existing direct construction stays available.
let owner = try await Services.makeOwned(seed: 1, service: mock)

// New convenience uses the existing generated builder, not a second DSL.
let owner = try await Services.makeOwnedWithOverrides(seed: 1) {
    $0.service = mock
    $0.optionalService = .some(nil)
}

// Existing validated presets can be reused without unpacking every property.
let owner = try await Services.makeOwnedWithOverrides(seed: 1) { $0 = preparedOverrides }
```

An already-cancelled task is rejected before the builder runs. The builder may
throw. It runs before any owner, live factory, child or
task is created. Its values forward to the same direct construction method.
No automatic effect preflight, scoped auto-close, task-local environment, or new
owner lifetime policy is implied. Existing explicit `close()` remains required.

Pass conditions: actual-plugin strict compilation for old direct calls and new
closure calls; empty containers; closure-valued inputs and child overrides;
MainActor and ordinary callers; cross-module visibility; optional `.some(nil)`;
throw-before-construction; overridden factory/dependency never starts; ordinary
macro output byte parity when owned generation is disabled. If overload
inference is ambiguous, use a uniquely named convenience rather than compiler
underscored ranking attributes or weakening types.

## 2. Support synchronous Lazy/Provider dependencies

Preserve the existing distinction: `Lazy` resolves an input or synchronous
shared/transient dependency; `Provider` invokes the synchronous transient resolver.
These remain non-Sendable wrappers. Reuse typed cells/resolvers and the existing
graph/availability/effect/ownership checks, with no new runtime service registry.
Do not add async targets, ignore cycles, adopt a borrowed child, or claim close
revokes synchronous values. Forward-reference, override, release, repeated
resolution, actor and wrong-target compiler fixtures must pass before accepting
the extension. A design review precedes implementation of cell wiring. The
legacy generated deferred support cell has unchecked Sendable inheritance;
owned generation must use a non-Sendable variant instead. Ordinary async
factories, and sendable on-demand cells, must not capture that mutable cell.
MainActor async consumption is qualified separately by actual compiler tests.

## 3. Find and reduce measured macro work

Use the exact same driver and phase boundaries for original, checkpoint, and
follow-up sources. First identify which parse/analysis/generation/format stages
dominate; then remove repeated work with a small invariant-preserving change.
Ordinary and owned scenarios must be separate. Do not rerun until a desired
number appears or infer complete build improvement from a microbenchmark.
Coordinate timing with other VM work and retain failed/uncertain runs.

## Still requiring supported Apple/compiler qualification

- Full public-module/package, SwiftUI feature-root and Apple-only runtime tests
- Swift 6.2 and 6.3 qualification; no minimum-version change is authorized
- Public symbol-graph baseline regeneration and reviewed intentional API delta
- Whole-app build, binary/heap and owner-heavy consumer comparisons

Assisted factories, collections, feature-root owner integration, custom actor
support and a product split are not silently promised by this follow-up.
Nominal `owner.container` migration remains explicit. No source/type erasure,
unchecked Sendable, automatic child ownership or initialization-default change.

## Rejected same-name overload

The first actual-plugin before/after canary found a silent behavior change:
`Parent.makeOwned { $0.service = 9 }` selected the existing child override closure
at checkpoint (parent 1, child 9), but the added overload selected the parent
builder (parent 9, child 2). A distinct `makeOwnedWithOverrides` name prevents
that ambiguity; a closure label alone can be omitted in Swift trailing syntax.
The two failed/successful binaries and logs remain in follow-up evidence.

## Measured bottleneck and bounded performance candidate

Diagnostic instrumentation of the same driver showed that model parsing and
validation are a small part of its total cost. The driver also includes generated
source reparsing and SwiftSyntax expansion machinery; its wall time is not a
complete application build metric. Do not turn an internal IR rewrite into a
performance claim without measuring these boundaries.

The selected source change only moves the name equality check before sibling
eligibility in `hasDuplicateManagedMemberName`. Eligibility reads syntax and
does not emit diagnostics or normalize/mutate names. For N eligible, uniquely
named properties its expensive calls fall from N(N+1) to 2N. The cheap sibling
name scan remains quadratic; this is not a claim of a fully linear algorithm.

The frozen original predicate matched 9,600 comparisons across declaration
shapes, names and actor policies. The full focused suite and actual plugin pass.
The separate uninstrumented two-module paired benchmark has a preregistered
local gate: upper descriptive block ratio at most 1.05 for both workloads, and
a 50-node point ratio at most 0.98. The 50-node case passed; the composite case
did not. Keep the small source candidate separable from the two DX improvements.
It has not earned a whole-macro performance approval, and the failed gate must
remain visible in any future PR or release recommendation. No repeat-until-pass
run was performed.
