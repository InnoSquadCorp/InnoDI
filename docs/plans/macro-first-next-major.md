# Macro-first next-major implementation plan

Status: the selected local foundation, opt-in ordering, typed-only prewarm,
explicit owner/view and synchronous-transient composition are implemented and
portably tested. Independent review and bounded local experiments are recorded; the failed full
test-image macro cost gate remains a qualification concern despite a passing
minimal-driver control. General ready-getter optimization was not adopted. Apple release qualification is pending. See the
[local results](../reviews/macro-first-results.ko.md).
Baseline: `6725e08b6da5d2ceeda61ed795adca5fadda564c` (unreleased 7.0 candidate).
Date: 2026-10-01. No next-major release number or release commitment is assigned.

## User outcomes first

The target is better performance **and** day-to-day developer experience than
alternatives in explicitly named scenarios. It is not a claim that one library
wins every use case. Internal IR consolidation is not a user outcome.

| Scenario | Baseline pain / observable | Candidate outcome and pass condition |
|---|---|---|
| Wire a 20-service feature | Explicit declarations plus declaration-order repair | Same macro authoring; no registry/wrapper required; construction-order prototype accepts an acyclic forward reference without rearranging declarations |
| Rename a prepared async service | String IDs and a separate hand-maintained plan | Generated typed selection; renamed references fail at compile time; zero handwritten provider-ID/dependency strings in the default path |
| Repair an invalid edge | Error code, anchor, notes, fix-it, repair iterations | Phase 1 byte-for-byte diagnostic/snapshot parity; later error changes need a fixture showing fewer repair steps or clearer location |
| Override two effects in concurrent tests | Generated `Overrides` / `withOverrides` | No regression in isolation or written statements; task-local operation effect tools can remain complementary |
| Start and end a feature | Eager task, on-demand cell and scope have distinct lifetimes | One explicit owner boundary for opted-in async providers; no undocumented child/copy cancellation; cancellation/retry/close tests prove the contract |
| Iterate a large container | Repeat scans for every edge | N=50/200/1000 scaling, unchanged expansions and validation; no added abstraction cost hidden in cold builds |

For DX pilots record authored nonblank lines, identifiers and separate artifacts
required, IDE/compiler error location, actionable diagnostics, edit/build cycles
until fixed, override statements, explicit lifetime actions, and migration edits.
Count generated code separately. Lines of code alone are not a usability score.
Use two real consumers only after access and any edits are authorized. No pilot
completion or usability time has been measured by this plan.

## Non-negotiable architecture

- `@DIContainer`, `@Provide`, `@Input`, explicit `@SubContainer` boundaries and
  generated Swift remain the primary user interface.
- Generated direct access/storage remains the steady-state sync path. No new
  runtime registry, reflection or service-locator escape hatch.
- Compile/build-time graph, effect and isolation checks remain enabled under
  their documented policy boundaries; ownership cycles still fail when DAG
  availability diagnostics are disabled.
- Runtime lifetime and value access are separate capabilities. Swift compiler
  witnesses check Swift types; source analysis never claims compiler knowledge.
- No `@unchecked Sendable` workaround, process-global syntax cache, reintroduced
  symbol-graph prebuild validator, or inferred factory purity.
- Keep Apple's platform contract and Swift 6.2 floor until a separate decision.
  Linux-only harness results do not establish Apple consumer support or parity.

## Decisions and phases

### Phase 1: indexed semantic availability, before any public break

Choose the smallest B3/F4 foundation: immutable source-independent descriptors
for name, availability kind and declaration index, plus an indexed query.
Adapt the macro's existing model once per validation using its compact member
array index, never `sourceOrder` (which also counts unmanaged/child declarations). Keep syntax anchors,
parser recovery, effect checks and emitted code in their existing layers.

`status(name, consumerIndex)` currently materializes member sets per reference.
The index builds in O(N) expected dictionary work and queries in expected O(1),
with O(N) additional storage. Full available-name sets remain O(N) and are built
only when explicitly requested. These are algorithmic bounds, not timings.

Duplicate declaration names must not trap or silently change error recovery:
retain whether *any* input exists, and the earliest sync/async shared index for
each name. Invalid consumer indexes and unknown names keep existing precedence.
Do not merge all parser models or invent a versioned graph schema in this step.

The graph collector intentionally records declared dependencies, including
ones unavailable for initialization. Do not filter those through availability:
that would hide invalid or ownership edges. Shared semantic interpretation will
be adopted one proven rule at a time, with parity fixtures rather than a forced
common object model. Phase 1 does not claim all collectors now use one IR.

Deliverables: core index, macro adapter, exhaustive/reference-model tests,
macro integration parity fixtures, reproducible focused scaling harness and
raw measurements, architecture review and patch review. No user API change,
no migration, no generated storage change. No workflow or public baseline edits.

### Phase 2: declaration order versus initialization order (B2)

The local prototype adds a named opt-in initialization policy. Keep property/diagnostic order
source-stable and generate initialization from a stable topological order.
Independent nodes tie-break by declaration index. Hard edges constrain init;
deferred ownership edges still constrain cycle validity and must not become
startup prerequisites merely because they retain a value.

```swift
// Current: reorder the declaration to make the hard dependency available.
@DIContainer
struct App {
    @Provide(.shared, factory: Config()) var config: Config
    @Provide(.shared, factory: { (config: Config) in API(config) }) var api: API
}
// Implemented local prototype; release qualification pending.
@DIContainer(initializationOrder: ContainerInitializationOrder.dependency)
struct App {
    @Provide(.shared, factory: { (config: Config) in API(config) }) var api: API
    @Provide(.shared, factory: Config()) var config: Config
}
```

This changes side-effect order and therefore cannot be marketed as an invisible
optimization. Do not infer purity from `effect: .none`. Keep explicit startup
side effects separate; propose order constraints only if consumer evidence needs
them. Block default changes until two authorized consumer traces show equivalent
identity and approved side-effect ordering and migration diagnostics exist.

### Phase 2b: typed synchronous prewarming prototype (bounded B4 slice)

Before unifying async ownership, improve the existing synchronous selection API:

```swift
// Existing API: accepts any PartialKeyPath, invalid selections throw at runtime.
try container.prewarm(\.metrics)
// Candidate generated API: cases exist only for sync on-demand shared providers.
container.prewarm(.metrics)
container.prewarm(.metrics, .analytics)
```

Generate a nested `_InnoDIPrewarmProvider` enum in the existing compiler-owned
reserved namespace and use direct switch dispatch. Do not generate a natural-name
`PrewarmProvider` alias: it can silently capture an ordinary payload type. The typed
operation returns no value and has no registration/resolution capability. The
first additive overload candidate failed the small-container macro budget
(+17.7% median at N=1; corrected descriptive paired-block interval 1.133–1.387), so it is not accepted.
The current breaking experiment replaces the key-path API with one typed
variadic method and no dispatch helper. Empty calls are nonthrowing no-ops.
Simple literal key-path calls can migrate mechanically after receiver type
resolution; dynamic/generic PartialKeyPath consumers need a concrete token or
explicit warming-closure adapter. This gap is part of the DX cost, not hidden
behind reflection. Dispatch each selected case once; do not scan every
provider for every selection. Types from another container, input/eager/async/
transient providers must be rejected by the compiler. Selection visibility follows
the container, like the existing Overrides/init control surface; it can expose
construction names for less-visible getters without exposing their values. Preserve actor isolation,
identity, selected order, repeated-selection caching and laziness of unselected
providers. No unchecked conformance or runtime reflection.

The initial natural nested name was rejected after a Swift 6.4 compiler canary
proved silent capture of an external enum with a matching case. The reserved
name avoids that ordinary-name capture and uses the existing `_InnoDI` authored
member prohibition. Explicit token annotations are less attractive:
`Container._InnoDIPrewarmProvider`; contextual `.metrics` calls stay concise.
This is not a claim of collision immunity for arbitrary user-authored imported
names in the compiler-reserved namespace. The exact public shape remains a local
prototype with release/API review pending. Compare generated-code/build-size growth with selection latency;
extra generated syntax is not free. The owner choice below is now explicit;
legacy eager tasks do not silently gain close/retry capabilities.

### Phase 3: typed preparation selection (B4), opt-in owner prototype (B1)

Generate provider tokens from the same declarations, not a second user-authored
registration DSL. Typed owner capabilities may select only owned async providers
from their associated container. Display/trace IDs stay strings; serialized IDs
are explicitly not compiler identity. Custom `DIAsyncPreparing` adapters keep
an explicit capability boundary for transactional retry.

The explicit `makeOwned` policy was selected on 2026-10-01. The generated
prototype is implemented locally and under compiler/runtime qualification; exact
release/API acceptance remains pending. No handwritten second graph is required:

```swift
// Current: users author scopes plus a parallel string-based plan.
let configuration = DIAsyncScope<Configuration>(providerID: "configuration") { ... }
let session = DIAsyncScope<Session>(providerID: "session") {
    try await Session(configuration: configuration.value())
}
let plan = try DIAsyncPreparationPlan(nodes: [
    .init(provider: configuration),
    .init(provider: session, dependencies: ["configuration"]),
])
let report = try await plan.prepare(["session"])

// Opt-in: macro-authored services plus generated owner-only selections.
@DIContainer(generateOwned: true)
struct FeatureContainer {
    @Provide(.shared, initialization: .onDemand, asyncFactory: loadConfiguration)
    var configuration: Configuration
    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { (configuration: Configuration) async throws in
                 try await Session(configuration: configuration)
             })
    var session: Session
}
let owner = try await FeatureContainer.makeOwned()
let report = try await owner.prepare(.session) // generated token, no string graph
let session = try await owner.container.session
await owner.close()
```

The generated names are `_InnoDIOwner`, `_InnoDIOwnedView` and
`_InnoDIOwnedProvider`, not natural-name aliases that can shadow payload types.
`generateOwned: false` (the default) does not emit or allocate this surface.
Opting in adds generated code even when a consumer still calls ordinary init;
macro expansion cannot know whether another source file calls `makeOwned`.

#### Accepted owner contract and migration

- `makeOwned` is `async throws`: it finishes setup and eager-task admission, not
  readiness. `prepare(.session)` waits for the selected dependency closure.
- Ordinary container identity/access stays unchanged. `owner.container` is a
  distinct generated view. Every owned async getter is `async throws`, even a
  factory that cannot itself throw, because cancellation/close are observable.
- Inputs and sync shared values keep their concrete types and ordinary lifetime.
  A returned service or sync value cannot be revoked by closing an owner.
- Copies of owner/view share scopes and terminal admission. Separate `makeOwned`
  calls are independent. Shared children are borrowed plain child values; parent
  close does not adopt or close them. Transient/assisted/deferred/feature-root and
  multibinding forms are explicitly diagnosed in this first owner slice rather
  than silently losing members. Owner mode requires normal DAG validation.
- Value overrides seed ready scopes without starting their factory. Their runtime
  preparation nodes omit factory dependency edges; the declared graph is still
  checked. Other declared eager roots retain their own independent startup.
- `cancel(.session)` cancels only selected running scopes. Ready, idle, failed,
  cancelled and closed states are unchanged. There is no admission pause and no
  implicit dependency propagation or all-selection atomic transaction. Each
  scope's actor transition is the cancellation point: work running then is
  cancelled, and a scope idle then may start afterward. Explicit retry preserves
  its factory and advances the generation; late old completions are rejected.
- `close()` first closes global admission, then closes scopes in reverse graph
  order. Concurrent calls join one completion. A read admitted before the barrier
  may win the scope-local race; later reads, including cached reads, throw closed.
  Close waits for lifecycle cleanup, not arbitrary user work that ignores task
  cancellation. It cannot revoke already-returned values.
- The runtime coordinator uses the existing lifecycle-only preparation protocol,
  never a heterogeneous service-value registry. Scopes retain an admission actor
  with no provider references, avoiding an owner/scope retain cycle. There is no
  new unchecked Sendable conformance or widened container/view Sendable promise.
- The internal generated cancellation callback may only cancel concrete scopes;
  it must not reenter owner lifecycle methods, because close joins its completion.

Migration: declarations gain one opt-in argument; call sites acquire/close an
owner and use a view. Code explicitly typed as the original container, its key
paths, protocol conformances and custom methods does not automatically accept or
appear on the view. Migrate consumer input to narrow service dependencies or the
explicit view type; do not promise identity-preserving conversion. MainActor
and caller-executor checks remain compiler witnesses. Custom global actors are
an explicit owner-mode limitation pending the conditional isolation spike.

### Phase 4: isolation (B5) and packaging (B6) as conditional spikes

Custom global actor support requires positive and wrong-executor compile-fail
fixtures on every supported compiler. Keep MainActor's safe generated surface.
Stop if required isolation cannot be expressed without unsafe conformance or a
compiler-floor increase; the latter is a user decision.

A runtime core split is justified only if measurements show lower consumer
build/runtime cost or actual portability demand. Existing optional SwiftUI and
testing products already provide boundaries. Do not split products to claim a
smaller file count. Measure package resolution, macro/plugin build artifacts and
linked app size separately. Product/import and support-symbol changes need an
explicit migration and version-alignment policy.

## Stop gate before broad breaking API work

Explicit owner mode was approved; its local implementation continues under the
contract above. Remaining product stop gates are:

1. Which release carries the new owner API and typed-only prewarm migration?
2. Any future child-owner adoption or additional transient/feature-root contract
   must be explicit; this prototype borrows shared plain children.
3. Is topological initialization opt-in permanently or eventually the default?
   Which existing side-effect order must migration preserve?
4. What compiler/platform floor and product/import names are allowed to change?

Do not treat approval to investigate/implement the track as acceptance of all
proposed API spellings, automatic release, remote PR publication or merge.

## Fair comparison and success gates

Pin exact source revisions for InnoDI before/after, Factory 3.4.1,
swift-dependencies 1.17.1, Needle v0.25.1 and Swinject 2.10.0 (report baseline
versions; revalidate pins at experiment start). Include hand-wired Swift as a
control. Libraries may require different compiler floors; compare on the same
supported Apple toolchain, OS, machine, optimization and workload. Do not run
only InnoDI's fast path against another library's full feature path.

| Workload | Runtime / memory | Build / binary | DX comparison |
|---|---|---|---|
| Trivial direct value, fixed hot service reads | checksum; construction separated from warm lookup p50/p95 | release text/data + stripped binary delta | declarations and access code |
| 20/200/1000-node sparse and dense DAG | identical construction count, identity and dependency work | clean build, warm no-op, leaf edit, container edit | graph wiring and diagnostic repair |
| Shared on-demand service, first and concurrent access | first latency, warm access, allocations, retained instances, peak RSS | generated code and binary delta | cache ownership clarity |
| Two independent async roots plus dependent child | same cancellation/close/retry policy, service workload and concurrency limit | compile cost of typed surface | setup lines and lifetime actions |
| Parallel tests overriding two effects | leak/interference oracle before timings | test-target build | override lines, setup/teardown, isolation failures |
| Feature hierarchy + explicit owner close | exact graph, child lifetime and deinit counts | generated/support artifact size | mount, escape, shutdown steps |
| Invalid edge/cycle/effect/isolation | not a runtime speed score | time to first actionable failure | compile versus runtime failure, anchor, repair count |

Where a library has no equivalent contract, report native support, required
adapter/user code and unsupported cells. Do not penalize effect-scoping libraries
for not being whole-object graph validators, or hide adapter costs. Provide
capability-matched and idiomatic-native views separately. No universal composite
score or winner is required; show per-scenario results and tradeoffs.

Measurement protocol:
- Record SHA/pin, Swift/Xcode/OS/CPU, architecture, memory, flags, invocation,
  dependency/cache state, generated workload seed and raw samples.
- Alternate before/after order; use the same resolved dependencies. Cold means
  fresh build directory with dependency-download time reported separately. Warm
  no-op and edit rebuild are separate, not an undifferentiated build average.
- Warm up runtime/microbenchmarks, retain at least 30 raw timing samples for
  publishable comparisons, report median/p95/dispersion. Use an observable
  checksum/noinline boundary to prevent eliminated service work.
- Resource measurements use equivalent process boundaries and service lifetimes;
  tool/plugin RSS is not app RSS, and archive size is not linked binary size.
- Microbenchmark the index **and** full macro expansion/consumer compilation to
  reveal abstraction/setup cost. No passing speed claim from a microbench alone.

Phase 1 pass gates: exact reference parity (including duplicate and malformed
inputs), existing diagnostics/expansions unchanged, strict-concurrency build of
the affected core/macro paths, O(N) stored index and expected O(1) lookup, and no
representative small-container macro or cold-build regression beyond 5%: use
30 paired measurements and a fixed-seed descriptive resampling interval of
the median ratio, resampling whole paired blocks when samples within a block
are correlated (report the independent block count, and do not interpret a
three-block interval as population-level 95% coverage); pass only if its upper bound is <=1.05, fail if its lower bound is >1.05,
and otherwise report inconclusive and collect more evidence. Target >=20% lower isolated dense lookup median at N=1000;
this is a local engineering target, not a competitor/product claim. Failure to
meet the small-container gate triggers simplify/revert, not baseline weakening.

Later release gates: all affected Apple suites and 6.2/6.3/6.4 consumer fixtures,
public API/migration audit, independent review, ownership race stress and runtime
resource checks. Any unmeasured cell remains explicitly unmeasured. Do not lower
existing CI budgets, relax validation, or claim competitor superiority to pass.

## Migration and risks

Phase 1 has no source migration. Keep its support types package-scoped so a
partial internal model does not become a public ABI contract. Later migration
must be versioned and idempotent: string selection -> generated tokens where
unambiguous; ambiguous custom plans require manual review; owner adoption is
explicit; eager effect and lifetime changes require compiler-guided call-site
edits; init reorder reports possible side effects rather than rewriting blindly.

Main risks: abstraction growth, parser/recovery divergence, falsely shared
ownership, new task/actor overhead, diagnostic churn, source-order side effects,
strict warnings from new compiler witnesses, minimum-compiler limitations and
unfair competitor comparisons. Each is attached to a gate above. F1 mock payload
release-under-lock remains a separate runtime correctness task; it is not fixed
by the index and will not be represented as an executed reproduction here.

## Independent architecture review

A read-only review on 2026-10-01 found no blocker to Phase 1. It required
compact-array indexing, duplicate union semantics, unknown-name precedence,
unmodified effect/local-validity checks, retention of deferred ownership edges,
and an equivalence-style regression gate rather than absence of significance.
Those constraints are incorporated above. Owner and default-order decisions remain open; the named-token opt-in ordering
prototype is authorized independently of those decisions.

## Dated implementation checkpoint — 2026-10-01

Phase 1's staged patch has no blocking independent-review finding. The baseline
focused Linux package passed 536 tests and the index candidate 541, including
two core tests exhaustively checking 4,681 sequences and three macro integration
tests. Existing snapshots/diagnostics were included. Whole-package Apple tests
are blocked by existing Darwin/os imports; the focused package excludes
MechanicalFixItTests and Apple-only targets. An invalid new test fixture was
corrected from an unmanaged stored property to a static property before the pass.

For the unchanged whole-macro composite-v2 fixture, 30 samples per version in
alternating blocks gave baseline median 281.6155 ms and candidate 277.1620 ms.
The initial row-resampling interval was 0.9321–1.0303, but treating samples in
a block as independent was too optimistic. Paired whole-block resampling gives
0.9365–1.1565 with only three blocks. The earlier 5% regression-gate pass claim
is withdrawn; whole-macro improvement or absence of regression is unproven.
The complexity/oracle evidence is separate from compile-time and app performance.
Raw evidence is retained separately, including compiler/manifest/binary hashes.

Phase 2 was prioritized next because it removes a concrete declaration-reordering
DX burden without deciding a new owner model. Its public spelling uses named
String tokens, following the existing ContainerRole compiler workaround; this
has not been verified on Swift 6.2/6.3. Default declaration order remains unchanged.
Independent review identified a normalized DAG-opt-out lookup corner, prompting
a shared syntax-free stable-order helper for precise codegen/preflight parity.
The entire breaking-change track is not complete, and no release is assigned.

### Phase 3b: synchronous transient composition (accepted local extension)

The 611-test checkpoint rejected every transient in `generateOwned` containers.
A common shared-service + transient-view-model graph therefore required splitting
one authored declaration into two. Remove that friction without turning a fresh
synchronous value into a lifecycle node:

- `@Provide(.transient, factory: ...)` keeps a synchronous, nonthrowing getter.
  Each read executes its typed resolver; a direct value override returns that
  same override on every read, as the ordinary container does.
- Capture only typed input/shared values or cells, transient resolvers, the
  direct override and trace owner. Never capture the owner/coordinator/view.
- Reuse factory-expression and stable-order helpers. Emit each transient factory
  once, in dependency order; diamond paths invoke it independently rather than
  duplicating generated source or caching values.
- Existing effect/cycle validation remains authoritative. Async transient,
  assisted, deferred Lazy/Provider and collection shapes remain unsupported in
  this phase. Shared providers cannot gain an illegal hard transient dependency.
- Transients do not become prepare/cancel/retry/status selection cases or tasks.
  `close()` closes owned async admission/work, not synchronous objects. Existing
  sync shared and new sync transient getters remain usable after close; callers
  own returned values. This is an explicit existing synchronous contract, not
  automatic disposal or value revocation.
- Preserve member visibility, MainActor/caller isolation, source `Self`, direct
  override short-circuiting, and disabled-option legacy output.

Required evidence: mixed actual-plugin graph, per-read identity/counters, diamond
nonmemoization, override bypass of lazy dependencies/factory, after-close sync
access alongside async closed rejection, actor/compiler-negative cases, release
of typed captures, and no owner references in resolver bodies. Qualify public
cross-module output again. The prior fixed checkpoint and score remain recorded;
reassess after this extension instead of presenting it as all B1–B6 complete.
