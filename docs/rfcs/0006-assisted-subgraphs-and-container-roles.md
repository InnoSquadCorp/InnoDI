# RFC 0006 — Assisted subgraphs and container roles

- **Status**: Draft
- **Authors**: InnoDI maintainers
- **Created**: 2026-09-03
- **Last updated**: 2026-09-03
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

## Non-goals

- Runtime registration, service lookup, property-injected service location, or
  graph mutation after container creation.
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
public enum DIContainerRole {
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
@DIContainer(.component, isolation: .mainActor)
public struct TrainingContainer {
    @Input public var repository: any TrainingRepository
    @Input(.assisted) public var routineID: Routine.ID

    @Provide(.shared, TrainingCoordinator.self, with: [\Self.repository, \Self.routineID])
    public var coordinator: TrainingCoordinator
}

@DIContainer(.root, isolation: .mainActor)
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

The child container must generate its own factory signature because it is the
only macro expansion with lexical access to the assisted declarations.
Conceptually, the component above generates:

```swift
extension TrainingContainer {
    public struct AssistedFactory {
        public func callAsFunction(
            routineID: Routine.ID,
            _ configure: (inout TrainingContainer.Overrides) -> Void = { _ in }
        ) -> TrainingContainer
    }
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

## Graph and diagnostic contract

Graph JSON v3 should add explicit assisted-input and factory-ownership
semantics. An assisted input is metadata on its owning container and is not a
globally resolvable node. Factory ownership is a hard ownership edge from the
parent container to the child container.

Required diagnostics include:

- assisted input declared on a container shape that cannot generate a factory;
- assisted factory requested for a child with no assisted inputs;
- parent binding targets an assisted input instead of a static input;
- missing, duplicate, or unknown static child binding;
- generated factory/helper name collision;
- access-level mismatch across a public component boundary;
- conflicting root/component compatibility markers during the 5.x runway.

Additive 5.x graph commands should include `--why`, `--dependents`, `--unused`,
and `--diff`. These commands are migration evidence, not a reason to delay them
until 6.0.

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
   `@DIContainer(.component, ...)`.
3. Convert `@DIHierarchyRoot` plus `@DIContainer(root: true, ...)` to
   `@DIContainer(.root, ...)`.
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

## Traceability

| Requirement | Acceptance criteria | Planned implementation | Evidence |
|---|---|---|---|
| FR-600-001 | AC-600-001, AC-600-002 | Child input model and generated `AssistedFactory` | TBD |
| FR-600-002 | AC-600-002, AC-600-003 | Parent factory ownership macro and build validator | TBD |
| FR-600-003 | AC-600-001 | Generated child construction and overrides | TBD |
| FR-600-004 | AC-600-003, AC-600-004 | Graph JSON v3 and renderers | TBD |
| FR-600-005 | AC-600-005 | `@Input` parser, codegen, diagnostics, migrator | TBD |
| FR-600-006 | AC-600-005, AC-600-006 | Container role parser and hierarchy validator | TBD |
| FR-600-007 | AC-600-005 | Schema-v1 report groundwork landed; 6.0 rewrite rules remain TBD | `InnoDIMigrationCoreTests` report and external-consumer coverage |

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
  `@_spi(Experimental)`; the external fixture verifies that boundary.
- Pilot one InnoSample flow.

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

## Review gate

This RFC remains Draft until maintainers record the chosen public spellings,
the three pilot results, migration coverage, graph schema review, macro
performance comparison, and a conforming-counterexample review showing that no
accepted implementation can satisfy the written requirements while falling
back to runtime service lookup.
