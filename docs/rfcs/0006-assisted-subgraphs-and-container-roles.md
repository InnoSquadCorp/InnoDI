# RFC 0006 — Assisted subgraphs and container roles

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-09-03
- **Last updated**: 2026-09-04
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

As of 2026-09-03:

- `5.1.0` is the latest stable tag and `main` is the unreleased `5.2.0`
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

The following read-only snapshot used each consumer's fetched `origin/main`
archive and the schema-v1 `InnoDI-Migrate --report` command from InnoDI commit
`65086345f8ba00f04107ca74e70e15df496ff68c`. A clean report proves only that
the current 5.x migration scanner found no required rewrite or blocker. It is
not a substitute for resolving the experimental revision and building a pilot.

| Consumer | Observed `origin/main` | Pinned InnoDI | Report | 6.0 implication |
|---|---|---:|---|---|
| InnoSample | `ee3d9409cb422635ff89e02f361e2693fa226e13` | `5.1.0` | `clean`; 175 Swift files, 0 changes, 0 diagnostics | First pilot candidate. Runtime `userID` and `assigneeID` values already enter through router/deep-link flows, so the pilot should introduce a dedicated detail child rather than reclassify the long-lived feature input bundle. |
| Mulbyul Apple | `ce91b1ee280acaa65e629ccf00bc4aa5a975d7dc` | `5.1.0` | `clean`; 449 Swift files, 0 changes, 0 diagnostics | Second pilot candidate. `routineID` and `sessionID` are created at Training navigation/session boundaries; the existing shared `TrainingFeatureContainer` input remains static while a nested routine/session child owns the assisted value. |
| BlPia Apple | `8404b2f81c6f4f4d7f43a5616c99722fb75714fc` | `3.0.1` | `blocked`; 158 Swift files, 7 `migrate.unqualified-ownership-ambiguous` diagnostics | Not a direct assisted-factory pilot. First qualify ownership and migrate the seven legacy `@Provide(concrete:)` sites onto the 5.x contract, then rerun the report and strict consumer build. |

This closes the static inventory portion of the adoption gate. Mulbyul remains
unverified as a runtime pilot until its exact package revision, build, and
per-child lifetime assertions are recorded. BlPia remains blocked before that
gate and must not be counted as a negative result for the assisted-factory
design itself.

### Runtime pilot evidence

| Consumer | Consumer commit | InnoDI revision | Verification | Result |
|---|---|---|---|---|
| InnoSample | `f3acdeea9e4dc9d1e4d1f19be2a90c675b165a38` | `8a1012ed8d9d5421cb31bd2106c5c7a679ecdd78` | Xcode 27.0, Tuist 4.202.5, `make verify-ci`; Remote 16 + feature 25 tests and generic iOS/embedded watch build | Runtime pilot verified against the parent-owner alias revision. A People route creates assisted detail children, proves per-child `.shared` isolation and override identity, and keeps the SPI revision explicit. |

The pilot also exposed a contract boundary rather than hiding it. The
deterministic SPI peer alias passes the strict external cross-module parent
fixture, satisfying the compilation portion of AC-600-002. In the same Xcode
target, however, another source file cannot name the generated peer directly;
adding a source-written typealias exposes the nested type name but still does
not make its generated initializer accessible. InnoSample therefore keeps a
hand-written `PeopleDetailFactoryPilot` wrapper beside the child declaration
and lets the parent coordinator own that wrapper. This is positive evidence
for FR-600-001/002/003, but FR-600-002 remains partial and AC-600-003 remains
open: the framework still needs a same-module bridge plus complete
child-to-parent binding diagnostics before the public spelling can freeze.

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

The exact spelling remains reviewable while this RFC is Draft. The semantic
roles are fixed for the prototype.

```swift
public enum ContainerRole {
    case local
    case component
    case root
}

public enum DIInputKind {
    case container
    case assisted
}
```

Illustrative source:

```swift
@DIContainerRole(.component, isolation: .mainActor)
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

@DIContainerRole(.root, isolation: .mainActor)
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

`validateDAG` remains an explicit narrow escape hatch. The prototype should
evaluate `isolation: .mainActor` against the existing `mainActor: true` API;
the major migration must not silently change executor behavior.

## Compile-time multibindings

The stage-2 preparation spelling uses one rename-safe, explicit contributor
list rather than implicit module discovery. It remains reviewable while this
RFC is Draft:

```swift
@DIContainerRole(.component)
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
or written-type-mismatched contributors. The first 5.2 SPI probe remains only
for pinned migration compatibility. Map keys, parent/child extension, and the
final accepted public attribute name remain separate design work.

## Graph and diagnostic contract

Graph JSON v3 should add explicit assisted-input and factory-ownership
semantics. An assisted input is metadata on its owning container and is not a
globally resolvable node. Factory ownership is a hard ownership edge from the
parent container to the child container. It should also distinguish a
multibinding collection from its ordered contribution edges.

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
   `@DIContainerRole(.component, ...)` during the preparation train. Final
   naming remains subject to RFC acceptance.
3. Convert `@DIHierarchyRoot` plus `@DIContainer(root: true, ...)` to
   `@DIContainerRole(.root, ...)`.
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
  contributions and graph JSON v3 records the ordered collection edges.

## Traceability

| Requirement | Acceptance criteria | Planned implementation | Evidence |
|---|---|---|---|
| FR-600-001 | AC-600-001, AC-600-002 | Child input model and generated `AssistedFactory` | The source-visible `@AssistedFactory` bridge passes separate-file same-target `@MainActor` and cross-module strict consumers with typed assisted calls, actor-correct override forwarding, and independent child shared storage |
| FR-600-002 | AC-600-002, AC-600-003 | Parent factory ownership macro and build validator | `@SubContainerFactory` owns the shared factory provider; whole-source tests cover complete bindings plus missing, duplicate, unknown, and assisted-as-static failures |
| FR-600-003 | AC-600-001 | Generated child construction and overrides | Partial: the SPI external-consumer fixture and InnoSample People route create children with distinct `.shared` identities and verify override identity |
| FR-600-004 | AC-600-003, AC-600-004 | Graph JSON v3 and renderers | Complete preparation implementation: nodes separate ordinary and assisted inputs; edges distinguish fixed ownership, assisted-factory ownership, and ordered contributions; JSON diff includes contributor order and exits 5 on drift |
| FR-600-005 | AC-600-005 | `@Input` parser, codegen, diagnostics, migrator | `@Input` and `@Input(.assisted)` normalize into the provider IR; generated input type aliases feed the assisted bridge without repeating source types |
| FR-600-006 | AC-600-005, AC-600-006 | Container role parser and hierarchy validator | Partial: `@DIContainerRole(.component/.root)` and `isolation: .mainActor` synthesize the existing hierarchy and actor contracts without weakening legacy `@DIContainer` diagnostics; final naming review and broader consumer pilots remain |
| FR-600-007 | AC-600-005 | Schema-v1 report plus idempotent 6.0 rewrite rules | `InnoDIMigrationCoreTests` cover input, role, isolation, option preservation, write, and second-pass stability; the strict public component fixture compiles the migrated spelling |
| FR-600-008 | AC-600-008 | Ordered collection binding code generation | Complete preparation implementation: public `@Multibinding` is injectable and overrideable; strict external runtime coverage proves order and shared/transient contributor lifetime behavior |
| FR-600-009 | AC-600-009 | Multibinding diagnostics and graph JSON v3 contribution edges | Complete preparation implementation: macro and serialized whole-source validators cover invalid contributor contracts, while schema v3 records contributor identity and order as contribution edges |

## Staged delivery

### 5.2.x — reversible groundwork

- Land this RFC as Draft and record measurement baselines.
- Add graph explainability commands and migration reporting.
- Prototype the child-owned factory in internal tests or an explicitly
  experimental public surface without deprecating 5.x declarations.
- The underscored `Experimental` SPI prototype now partitions existing
  `@Provide(.input)` members into static and assisted inputs and has a
  cross-module runtime fixture proving that separate factory calls own
  separate `.shared` storage. Its attribute and generated type names are not
  candidates for source compatibility. Its temporary string-literal member
  list is validated against direct inputs at compile time; it exists only to
  avoid the self-referential key-path limitation of an attached type attribute
  and is not the proposed 6.0 `@Input(.assisted)` syntax. A public pilot
  container and any API exposing its generated factory must also be marked
  `@_spi(Experimental)`; the external fixture verifies that boundary. The
  child also emits a deterministic SPI peer alias so a parent in another file
  or module can own the factory through ordinary `@Provide(..., with:)`
  key-path wiring. This satisfies AC-600-002 without freezing the alias name;
  a dedicated child-to-parent binding validator remains 6.0 work.
- Public `@Multibinding` generates one injectable ordered local collection from
  contributor key paths. Macro, serialized build-validation, graph-v3, and
  strict external runtime fixtures cover diagnostics, deterministic order,
  shared/transient lifetime behavior, injection, and overrides. The
  underscored SPI remains only as compatibility evidence for pinned pilots.
- Pilot one InnoSample flow. Completed at consumer commit `f3acdee` against
  InnoDI `8a1012e`; the full consumer gate and per-child lifetime assertions
  pass, while the required local wrapper records the remaining FR-600-002
  same-module bridge and binding-diagnostics gap.

### Later 5.x — adoption runway

- Pilot Mulbyul and BlPia flows against an exact package revision.
- Freeze names only after expansion, strict-concurrency, graph, and consumer
  fixtures pass.
- Ship deprecations and the idempotent rewrite after the RFC is Accepted.

### 6.0.0 — stable contract

- Remove the superseded markers and `.input` provider spelling.
- Publish graph JSON v3 and the final migration guide.
- Require exact-tag external consumer validation before publication.

## Open questions

- Should the parent surface be named `@SubContainerFactory`, or should a
  factory mode be added to `@SubContainer` without overloading lifetime scope?
- Should the generated override configuration be a trailing closure, an
  explicit `overrides:` argument, or both?
- Can `isolation: .mainActor` replace `mainActor: true` without creating less
  readable diagnostics on currently supported Swift toolchains?
- Should the typed SwiftUI bridge remain a macro or become a non-macro result
  builder? This does not block the assisted-factory prototype.
- Which two real adopter flows satisfy the promotion gate after the InnoSample
  pilot?
- Should the stable collection declaration be `@Multibinding`, a `@Provide`
  construction form, or a separate `@IntoCollection` contribution marker?
- Does 6.0 ship ordered arrays only, or also keyed maps after duplicate-key and
  cross-module extension semantics are proven?

## Review gate

This RFC remains Draft until maintainers record the chosen public spellings,
the three pilot results, migration coverage, graph schema review, macro
performance comparison, and a conforming-counterexample review showing that no
accepted implementation can satisfy the written requirements while falling
back to runtime service lookup. One of the three runtime pilots is currently
recorded.
