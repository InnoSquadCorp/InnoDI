# RFC 0006 — Assisted subgraphs and container roles

- **Status**: Draft (promotion review)
- **Authors**: InnoDI maintainers
- **Created**: 2026-09-03
- **Last updated**: 2026-09-06
- **Target release**: Experimental groundwork in 5.2.x; stable contract in 6.0.0
- **Supersedes in part**: RFC 0004 macro-consolidation candidates 1 and 3

## Summary

InnoDI 6.0 should preserve compile-time graph validation while adding one
missing composition boundary: a child graph whose framework-owned dependencies
come from its parent but whose runtime values are supplied when the feature is
entered.

The proposed release-defining surface is an **assisted subgraph factory**. A
child container declares ordinary container inputs separately from assisted
inputs. The child macro generates the complete factory call signature; a
parent only provides the child's static dependency contract. This keeps the
design valid across module boundaries, where an attached parent macro cannot
inspect a child declaration's members.

The same major release separates input source from provider lifetime and folds
root/component markers into an explicit container role. Additive graph-query
and migration support ships first on the 5.x train so adopters can measure and
migrate before the old spelling is removed.

6.0 should also add deterministic compile-time multibinding for ordered
collections of same-typed providers. Contributions stay explicit and
source-visible; InnoDI does not scan loaded modules or mutate a registry at
runtime.

## Verified baseline

As of 2026-09-05:

- `5.1.0` is the latest stable tag and `main` is the unreleased `6.0.0`
  development train.
- The current `@SubContainer` contract can forward parent-owned `.input`
  values, but it cannot expose creation-time values such as an item identifier,
  document, route payload, or authenticated user in a generated child-factory
  signature.
- A static scan of 17 local InnoSquad repositories found 130
  `@DIContainer` declarations, 158 `@Provide(.input)` declarations, 57
  `@Provide(.transient)` declarations, and 5 `@SubContainer` declarations.
  The repositories resolve different InnoDI versions, so these counts are
  directional adoption evidence rather than a compatibility census.
- InnoSample, Mulbyul, and BlPia contain representative parent code that
  manually constructs feature containers from parent dependencies and
  runtime state.
- `@GenerateMock` and scoped task-local overrides remain independent
  experimental surfaces. Neither is promoted merely because 6.0 is a major
  release.

### Exact consumer adoption snapshot

The validated 6.0 code candidate is
`f1a3eaccf19bfc43164de3621c9197c731d92342`. `InnoDI-Doctor` analyzed the
actual Swift/Tuist layouts and the three committed consumer pilots resolved
that exact revision. A read-only Doctor result is configuration evidence; it
is not by itself a runtime pilot.

| Consumer | Consumer state | Exact candidate evidence | Result |
|---|---|---|---|
| InnoSample | committed and pushed on main as `ec88716` | Doctor: 178 Swift files, 0 proposed/applied/second-pass changes; migration check; DAG; Remote 16 tests; feature 25 tests; generic iOS and embedded watch build | Public assisted-factory, `DIContainerHost`, `@Input`, and explicit container-role pilot verified. The People route proves per-child `.shared` isolation, override identity, host loading/failure/retry, and removes the manual state wrapper. The official `make verify-ci` passes. |
| BlPia Apple | committed and pushed branch pilot `c12560d`; original dirty checkout preserved | Doctor: 160 Swift files, 0 diagnostics/changes; unchanged second pass; DAG; 10 test schemes; generic iOS and embedded watch build | The final strict hierarchy gate detected seven factory-created containers incorrectly marked as cross-module `component` ownership; the pilot now uses `local` roles for those `@Provide`-owned containers and passes the full gate. This is a committed adopter vote. |
| Lynceus | committed and pushed branch pilot `3edb77b`; original main checkout unchanged | Doctor: 81 Swift files, 0 diagnostics/changes; unchanged second pass; actual 2-container full-root DAG; 41 tests; macOS build | Fully qualified role/input/provide/subcontainer vocabulary and command-plugin analysis pass. This is a committed adopter vote. |
| Mulbyul Apple | original checkout and user changes preserved at committed HEAD `092ff951`; no source commit or migration applied | A fresh isolated clone generated its Tuist workspace against promotion head `2da86f7`; the aggregate test build then stopped at `DomainContainer.swift:5` because 6.0 replaces legacy `@Provide(.input)` with `@Input`. Read-only Doctor scanned 481 Swift files, proposed one safe path, and failed closed on nine unqualified ownership paths without writing. | This is explicit negative compatibility and migration-boundary evidence, not a committed adopter vote. |

The original SPI pilot exposed same-target visibility and initializer-access
gaps rather than hiding them. The public source-visible nested bridge passes
the separate-file same-target `@MainActor` fixture and strict cross-module
parent fixture. Whole-source validation rejects missing, duplicate, unknown,
assisted-as-static, and public access-level mismatch contracts at the source
declaration. The Mulbyul checkout remains explicit test-only evidence rather
than being silently counted as a successful pilot. Its isolated failure proves
that an unchanged 5.x consumer requires the documented 6.0 source migration;
it does not justify restoring the removed legacy spelling or mutating the
owner's working tree.

## Problem definition

Static composition works well when every input is available at the application
root. Feature entry often combines two different sources:

1. long-lived dependencies owned by the parent graph; and
2. values known only at navigation, session, window, document, or request time.

Today adopters must manually call a child initializer at those boundaries. The
manual path is type checked by Swift, but it is not represented as InnoDI
ownership, cannot participate completely in graph artifacts, and duplicates
composition code in application modules.

The current public vocabulary also conflates source and lifetime:
`.input` sits beside `.shared` and `.transient` in `DIScope`. Root and component
roles require stacked macros whose responsibilities are split between graph
rendering, generated dependency contracts, and hierarchy validation.

## Goals

- **FR-600-001**: Generate a typed assisted factory from the child container,
  including one named parameter for every assisted input.
- **FR-600-002**: Allow a parent graph to provide the factory's static
  dependency contract through rename-safe key-path bindings.
- **FR-600-003**: Give every factory-created child its own container lifetime,
  including independent `.shared` storage and per-child overrides.
- **FR-600-004**: Represent assisted inputs and factory ownership in graph
  artifacts without treating runtime values as resolvable provider nodes.
- **FR-600-005**: Separate externally supplied inputs from framework-created
  provider lifetimes in the public declaration grammar.
- **FR-600-006**: Replace stacked root/component markers with one explicit
  container role while preserving opt-in rooted hierarchy validation.
- **FR-600-007**: Provide a mechanical 5.x-to-6.0 migration report and rewrite
  for every removed declaration spelling.
- **FR-600-008**: Aggregate an explicit ordered list of same-typed synchronous
  providers while preserving each contributor's lifetime and override behavior.
- **FR-600-009**: Represent a collection binding and its contributors in graph
  artifacts and reject unknown, duplicate, async, or mismatched contributions
  with stable diagnostics.

## Non-goals

- Runtime registration, service lookup, property-injected service location, or
  graph mutation after container creation.
- Classpath/module scanning or declaration-order discovery of multibinding
  contributors. Contribution membership and order must be explicit.
- Reflection-based discovery of child inputs.
- Arbitrary user-defined lifetime scopes. Session, window, document, and
  request lifetimes should first be modeled as owned child-container instances.
- Promotion of `@GenerateMock` or scoped task-local overrides without their
  existing independent acceptance and adoption gates.
- General support for class, actor, enum, or generic containers.
- A minimum platform-version increase unless an accepted implementation
  requires one.

## Proposed public vocabulary

The following spelling is the candidate 6.0 contract. Implementation and
evidence freeze it for promotion review; formal RFC acceptance remains pending.

```swift
public enum ContainerRole {
    public static let local = "local"
    public static let component = "component"
    public static let root = "root"
}

public enum DIInputKind {
    case container
    case assisted
}
```

Illustrative source:

```swift
@DIContainerRole(
    role: ContainerRole.component,
    mainActor: true
)
public struct TrainingContainer {
    @Input public var repository: any TrainingRepository
    @Input(.assisted) public var routineID: Routine.ID

    @Provide(.shared, TrainingCoordinator.self, with: [\Self.repository, \Self.routineID])
    public var coordinator: TrainingCoordinator

    @AssistedFactory(
        TrainingContainer.self,
        static: [\TrainingContainer.repository],
        assisted: [\TrainingContainer.routineID]
    )
    public struct AssistedFactory {}
}

@DIContainerRole(
    role: ContainerRole.root,
    mainActor: true
)
public struct AppContainer {
    @Provide(.shared, factory: LiveTrainingRepository())
    public var repository: any TrainingRepository

    @SubContainerFactory(
        TrainingContainer.self,
        bindings: [
            (child: \TrainingContainer.repository, parent: \AppContainer.repository),
        ]
    )
    public var training: TrainingContainer.AssistedFactory
}

let child = appContainer.training(routineID: selectedRoutineID)
```

`@Input` is a declaration-source marker, not a runtime property wrapper. The
container macro remains the storage and initializer owner. `@Provide` keeps
only framework-created lifetime cases such as `.shared` and `.transient`.

## Child-owned assisted factory

Swift cannot make a nested nominal type introduced by a member macro visible
to another source file in the same target during that compilation. The child
therefore declares an empty source-visible nested `AssistedFactory`; its macro
fills the implementation. Rename-safe child key paths partition static and
assisted inputs without repeating their types. Each `@Input` emits a hidden
type alias used only by generated signatures. Conceptually, the component
above completes:

```swift
extension TrainingContainer.AssistedFactory {
        public func callAsFunction(
            routineID: Routine.ID,
            _ configure: (inout TrainingContainer.Overrides) -> Void = { _ in }
        ) -> TrainingContainer
}
```

The actual factory stores a generated static dependency value supplied by the
parent. It does not capture a service locator or defer dependency-name lookup
to runtime.

An assisted factory is generated only when at least one assisted input exists.
An ordinary fixed `@SubContainer` remains the preferred surface when the child
has no runtime inputs.

## Container roles

- `.local` is the default and generates the current local container surface.
- `.component` generates the cross-module dependencies contract currently
  owned by `@DIComponent`.
- `.root` activates rooted hierarchy validation and graph-root pruning. This
  combines the current `@DIHierarchyRoot` and `root: true` responsibilities.

Root inference is rejected. A workspace that has components but intentionally
does not model one whole root must not acquire diagnostics merely by upgrading.

`validateDAG` remains an explicit narrow escape hatch. The prototype preserves
the existing `mainActor: true` API; the major migration must not silently
change executor behavior.

## Compile-time multibindings

The accepted spelling uses one rename-safe, explicit contributor list rather
than implicit module discovery:

```swift
@DIContainerRole(role: ContainerRole.component)
public struct NetworkContainer {
    @Provide(.shared, factory: AuthInterceptor())
    public var auth: any RequestInterceptor

    @Provide(.transient, factory: LoggingInterceptor())
    public var logging: any RequestInterceptor

    @Multibinding([\Self.auth, \Self.logging])
    public var interceptors: [any RequestInterceptor]
}
```

The literal key-path order is the output order. Reading the collection resolves
each contributor according to its own lifetime, so a shared contributor keeps
its identity and a transient contributor is recreated. Contributor overrides
remain authoritative. The collection is a normal injectable transient graph
node and has its own override slot. Both macro expansion and the serialized
whole-source build gate reject invalid, empty, duplicate, unknown, asynchronous,
or written-type-mismatched contributors. The first 5.2 SPI probe was removed
after the public contract and migration path replaced its evidence.
Keyed/provider collections and explicit cross-module composition are provided
as runtime types; automatic module discovery remains intentionally out of
scope.

## Graph and diagnostic contract

Graph JSON v5 records explicit assisted-input, factory-ownership, provider,
canonical wiring, and contribution semantics. An assisted input is metadata on its owning
container and is not a globally resolvable node. Factory ownership is a hard
ownership edge from the parent container to the child container. Provider
identity includes lifetime, initialization, isolation, effect, canonical
factory-parameter targets and deferred kinds, child-input-to-parent-provider
binding pairs, and contribution order while excluding source position from
semantic diff.

Required diagnostics include:

- assisted input declared on a container shape that cannot generate a factory;
- assisted factory requested for a child with no assisted inputs;
- parent binding targets an assisted input instead of a static input;
- missing, duplicate, or unknown static child binding;
- generated factory/helper name collision;
- access-level mismatch across a public component boundary;
- conflicting root/component compatibility markers during the 5.x runway.
- empty, duplicate, unknown, async, or differently typed multibinding
  contributors, plus generated collection-name collisions.

Additive 5.x graph commands should include `--why`, `--dependents`, `--unused`,
and `--diff`. These commands are migration evidence, not a reason to delay them
until 6.0. `--diff ... --check-contract` must return 0 for an unchanged graph
and a distinct exit code for any scope, node, or edge drift so CI cannot accept
an unreviewed contract change.

## Failure and recovery behavior

- Invalid declarations fail at macro expansion or build validation; generated
  accessors must not defer malformed graphs to `fatalError`.
- If cross-module source is unavailable to an attached macro, build support
  validates the serialized container contract. The parent expansion never
  guesses the child's assisted signature.
- A failed automated migration leaves the source site unchanged and reports a
  stable diagnostic requiring human review.
- Existing 5.x declarations continue to compile during the experimental
  runway. Removal occurs only in 6.0 after the codemod and consumer fixtures
  are green.

## Migration

The `InnoDI-Migrate` sequence is intentionally mechanical:

1. Convert `@Provide(.input)` to `@Input`.
2. Convert `@DIComponent` plus `@DIContainer` to
   `@DIContainerRole(role: ContainerRole.component, ...)`.
3. Convert `@DIHierarchyRoot` plus `@DIContainer(root: true, ...)` to
   `@DIContainerRole(role: ContainerRole.root, ...)`.
4. Preserve `validateDAG` and actor-isolation arguments exactly.
5. Leave manual child construction unchanged unless the tool can prove the
   full assisted-factory transformation; report those sites as candidates.
6. Replace string-based SwiftUI environment member mappings only after the
   typed bridge spelling is accepted.

Migration must be idempotent and support report-only mode before write mode.

## Alternatives considered

### Parent-side signature generation

Rejected. An attached parent macro cannot reliably inspect a child declaration
in another module, so it would need duplicated parameter declarations or
unverified generated calls.

### Runtime argument dictionary

Rejected. `[String: Any]` or type-keyed lookup removes named Swift call
signatures, weakens diagnostics, and turns composition into runtime
registration.

### More built-in scopes

Deferred. Adding `.session`, `.window`, or `.request` does not solve how those
graphs receive their runtime identity. An owned assisted child makes the
lifetime boundary explicit without global scope machinery.

### Keep `.input` inside `DIScope`

Rejected for 6.0. It minimizes migration but preserves the source/lifetime
conflation that makes assisted inputs hard to explain and extend.

## Acceptance criteria

- **AC-600-001** (`FR-600-001`, `FR-600-003`): A fixture creates two children
  with different assisted values and proves their `.shared` providers are not
  shared with each other.
- **AC-600-002** (`FR-600-001`, `FR-600-002`): A cross-module fixture compiles
  a parent-owned factory without the parent repeating assisted parameter types.
- **AC-600-003** (`FR-600-002`, `FR-600-004`): Invalid static/assisted binding
  combinations produce stable diagnostics in macro and build-support tests.
- **AC-600-004** (`FR-600-004`): Graph JSON and human renderers distinguish
  factory ownership from provider dependency edges.
- **AC-600-005** (`FR-600-005`, `FR-600-006`, `FR-600-007`): The migrator
  rewrites representative 5.1 source idempotently and the result passes the
  strict-concurrency consumer fixture.
- **AC-600-006** (`FR-600-006`): Rooted hierarchy diagnostics activate for an
  explicit `.root` and remain inactive without one.
- **AC-600-007** (`FR-600-001` through `FR-600-006`): Root-package and
  synthetic-consumer macro measurements remain within the release gate.
- **AC-600-008** (`FR-600-008`): A strict-concurrency external fixture proves
  contributor order, shared/transient lifetime behavior, and override flow.
- **AC-600-009** (`FR-600-009`): Macro and graph tests reject invalid
  contributions and graph JSON v5 records the ordered collection edges.

## Traceability

| Requirement | Acceptance criteria | Planned implementation | Evidence |
|---|---|---|---|
| FR-600-001 | AC-600-001, AC-600-002 | Child input model and generated `AssistedFactory` | The source-visible `@AssistedFactory` bridge passes separate-file same-target `@MainActor` and cross-module strict consumers with typed assisted calls, actor-correct override forwarding, and independent child shared storage |
| FR-600-002 | AC-600-002, AC-600-003 | Parent factory ownership macro and build validator | `@SubContainerFactory` owns the shared factory provider; whole-source tests cover complete bindings plus missing, duplicate, unknown, and assisted-as-static failures |
| FR-600-003 | AC-600-001 | Generated child construction and overrides | The public external-consumer fixtures and InnoSample People route create children with distinct `.shared` identities and verify override identity |
| FR-600-004 | AC-600-003, AC-600-004 | Graph JSON v5 and renderers | Complete: nodes separate ordinary and assisted inputs; provider contracts and edges distinguish fixed ownership, assisted-factory ownership, canonical binding pairs, and ordered contributions; JSON diff includes provider semantics and contributor order and exits 5 on drift |
| FR-600-005 | AC-600-005 | `@Input` parser, codegen, diagnostics, migrator | `@Input` and `@Input(.assisted)` normalize into the provider IR; generated input type aliases feed the assisted bridge without repeating source types |
| FR-600-006 | AC-600-005, AC-600-006 | Container role parser and hierarchy validator | Complete candidate: `@DIContainerRole(role: ContainerRole.component/.root)` and `mainActor: true` synthesize the existing hierarchy and actor contracts without weakening legacy `@DIContainer` diagnostics; Swift 6.2 and 6.4 external lanes pass |
| FR-600-007 | AC-600-005 | Schema-v1 report plus idempotent 6.0 rewrite rules | `InnoDIMigrationCoreTests` cover input, role, isolation, option preservation, write, and second-pass stability; the strict public component fixture compiles the migrated spelling |
| FR-600-008 | AC-600-008 | Ordered collection binding code generation | Complete preparation implementation: public `@Multibinding` is injectable and overrideable; strict external runtime coverage proves order and shared/transient contributor lifetime behavior |
| FR-600-009 | AC-600-009 | Multibinding diagnostics and graph JSON v5 contribution edges | Complete: macro and serialized whole-source validators cover invalid contributor contracts, while schema v5 records provider identity, canonical wiring, and order as contribution edges |

## Staged delivery

### 5.2.x — reversible groundwork

- Land this RFC as Draft and record measurement baselines.
- Add graph explainability commands and migration reporting.
- Prototype the child-owned factory in internal tests or an explicitly
  experimental public surface without deprecating 5.x declarations.
- The underscored `Experimental` SPI prototype partitioned existing
  `@Provide(.input)` members into static and assisted inputs and has a
  cross-module runtime fixture proving that separate factory calls own
  separate `.shared` storage. Its attribute and generated type names are not
  candidates for source compatibility. Its temporary string-literal member
  list is validated against direct inputs at compile time; it exists only to
  avoid the self-referential key-path limitation of an attached type attribute
  and is not the proposed 6.0 `@Input(.assisted)` syntax. A public pilot
  container and any API exposing its generated factory must also be marked
  `@_spi(Experimental)`; the external fixture verifies that boundary. The
  child also emitted a deterministic SPI peer alias so a parent in another file
  or module can own the factory through ordinary `@Provide(..., with:)`
  key-path wiring. This satisfies AC-600-002 without freezing the alias name;
  the probe was removed after the public bridge, validator, and InnoSample
  migration replaced its evidence.
- Public `@Multibinding` generates one injectable ordered local collection from
  contributor key paths. Macro, serialized build-validation, graph-v4, and
  strict external runtime fixtures cover diagnostics, deterministic order,
  shared/transient lifetime behavior, injection, and overrides. The
  underscored SPI was removed after the public path replaced it.
- Pilot one InnoSample flow. The assisted factory and container-host migration
  completed at consumer commit `ec88716` against InnoDI `f1a3eac`; the full
  local consumer gate and per-child lifetime assertions pass without an SPI
  import, local wrapper, or manual SwiftUI state owner.

### Later 5.x — adoption runway

- Pilot BlPia and Lynceus flows against an exact package revision; retain
  Mulbyul as read-only/test-only evidence unless its owner later changes scope.
- The candidate spelling was frozen after expansion, strict-concurrency,
  graph, and consumer fixtures passed; formal acceptance remains pending.
- After acceptance, ship deprecations and the idempotent rewrite from this
  contract.

### 6.0.0 — stable contract

- Remove the superseded markers and `.input` provider spelling.
- Publish graph JSON v4 and the final migration guide.
- Require exact-tag external consumer validation before publication.

## Candidate decisions and adopter evidence

- Keep `@SubContainerFactory` separate from fixed `@SubContainer`; factory
  ownership and fixed child ownership remain distinct graph contracts.
- Keep the generated trailing override-application closure. It preserves typed
  child overrides without adding an untyped configuration surface.
- Keep `mainActor: true` and the required string-backed `ContainerRole` token.
  Swift 6.2.3 crashes while matching the public enum form in this multi-role
  attached macro, and the chosen spelling passes Swift 6.2 and 6.4 lanes.
- Use the non-macro `DIContainerHost`/owner runtime types for SwiftUI lifecycle
  rather than adding a second macro or result-builder DSL.
- Keep `@Multibinding` as the explicit local array declaration. Keyed and
  provider collections plus cross-module composition are explicit runtime
  contracts; automatic discovery and `@IntoCollection` are out of scope.
- The two additional committed adopter votes are BlPia `c12560d` and Lynceus
  `3edb77b`. Mulbyul remains outside the mutation scope by explicit user
  direction.

## Acceptance gate

Maintainers may accept the chosen public spellings only after the dedicated
promotion pull request completes its seven-calendar-day review cooldown, no
earlier than `2026-09-12T12:54:47Z`, and receives human maintainer approval.
Migration coverage, schema-v5 review, strict toolchain/platform gates,
macro/runtime performance evidence, conforming-counterexample review, and
three committed consumer pilots are recorded on the candidate; the acceptance
gate remains pending. Mulbyul's exact promotion-head read-only run records the
expected `@Provide(.input)` source break plus fail-closed Doctor diagnostics;
it remains test-only evidence and is not counted as an adopter promotion vote.
