# CLAUDE.md

This file provides repository-local guidance for Claude Code style agents.

## Project Overview

InnoDI is a macro-driven dependency injection framework for Swift. The package
ships:

- macro-generated DI containers
- compile-time and build-time validation
- a dependency-graph CLI
- optional cross-module hierarchy validation
- SwiftUI integration helpers in `InnoDISwiftUI`

## Build and Test Commands

### Build

```bash
swift build
swift build --target InnoDI
swift build --target InnoDIMacros
swift build --target InnoDI-DependencyGraph
```

### Test

```bash
swift test --no-parallel
swift test --no-parallel -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
swift test --filter InnoDIMacrosTests
swift test --filter InnoDIDependencyGraphCLITests
```

### DocC

```bash
Tools/generate-docc.sh
```

## Snapshot Workflows

### Macro snapshots

Macro tests use:

- `assertMacroExpansionSnapshot`
- `assertMacroExpansionInline`
- `assertMacroExpansionDiagnosticCodes`

Record snapshots with:

```bash
Tools/record-macro-snapshots.sh
Tools/record-macro-snapshots.sh DIContainerMacroTests
```

### CLI renderer snapshots

Renderer snapshots live under:

```text
Tests/InnoDIDependencyGraphCLITests/__Snapshots__/GraphRendererSnapshotTests/
```

Record them with:

```bash
Tools/record-cli-snapshots.sh
Tools/record-cli-snapshots.sh InnoDIDependencyGraphCLITests
```

## Architecture

### Module layout

1. `InnoDI`
   - public macros and runtime types
   - source doc comments that feed Quick Help and DocC
2. `InnoDIMacros`
   - container generation, validation, diagnostics, SwiftUI helper macros
3. `InnoDICore`
   - shared parsing and graph utilities
4. `InnoDIBuildSupport`
   - coordinated validation, artifact writing, cache and lock handling
   - a plugin snapshot holds every dependency target, InnoDI's own sources
     among them, so key semantic lookups by declaring target, not by an
     unqualified path, and never build them with
     `Dictionary(uniqueKeysWithValues:)`, which traps on a repeated path
5. `InnoDIWorkspaceAnalysis`, `InnoDIDependencyGraphCore`, `InnoDIDependencyGraphCLI`
   - full-source analysis, graph collection/query/contracts, JSON/Mermaid/DOT/ASCII rendering
   - `InnoDI-DependencyGraph` is the executable entry point
6. `InnoDISwiftUI`
   - environment bridge, feature-root helpers, and explicit host lifecycle
   - re-exports InnoDI but not SwiftUI; files that use SwiftUI, including
     through generated `SwiftUI.` qualifiers, import it themselves
   - `DIContainerHostOwner` is `@Observable` and observes only `phase`; keep
     every other stored property `@ObservationIgnored`. Observation notifies
     before the store, so `publish(_:)` must keep draining re-entrant
     publications instead of assigning `phase` from inside a notification
7. `InnoDITesting`, `InnoDIMigrationCore`, `InnoDIDoctorCore`
   - test support, migration planning/rollback, and project diagnostics
   - `InnoDI-Migrate`, `InnoDI-Doctor`, and `InnoDI-DeferredAliasScan` are CLI tools

### `@DIContainer`

The accepted 6.0 grammar separates the ordinary container from hierarchy and
isolation configuration:

- `@DIContainer` or `@DIContainer(validateDAG: false)` for an ordinary container.
- `@DIContainerRole(role: ContainerRole.local, mainActor: true)` for actor isolation.
- `@DIContainerRole(role: ContainerRole.component)` for a mountable feature.
- `@DIContainerRole(role: ContainerRole.root)` for strict rooted validation.

Use named `ContainerRole` tokens, not arbitrary strings. Do not restore the
old `@DIContainer(root:mainActor:)` grammar. `validateDAG:` is also accepted on
the role macro. A declaration uses one container macro, not both.

`@DIContainer` synthesizes:

1. a primary `init(...)`
2. a nested `Overrides`
3. a convenience `init(<inputs...>, _ applyOverrides: ...)`
4. four `withOverrides` effect overloads

For a container without `mainActor: true`, the generated `async` and
`async throws` `withOverrides` methods and their operation closure types must
be `nonisolated(nonsending)`. This preserves the caller's actor executor and
keeps arbitrary non-`Sendable` containers and closures from crossing isolation.
Keep synchronous overloads unchanged. Every `mainActor: true` overload and
operation closure remains `@MainActor`.

Every container, including a truly empty one, synthesizes the complete
overrides scaffolding. A user-declared nested `Overrides` type is a terminal
`container.overrides-name-conflict` error in InnoDI 6.0; never generate a
partial primary-initializer-only surface.

Every stored instance member in a container must use a supported management
macro (`@Input`, `@Provide`, `@Multibinding`, `@SubContainerFactory`, or
`@SubContainer`); computed and type properties remain available. Emit
`container.unmanaged-stored-property` before initializer generation otherwise.

An explicitly `private` container is unsupported in 6.0 because sibling
containers cannot access its generated mount surface. Require `fileprivate`
for same-file mounting or default access inside a private namespace.

Only effectively non-generic structs at file scope or inside non-generic
nominal declarations are supported; extension/executable-scope declarations
are rejected. Keep the full-source preflight enabled to cover attached-macro
ancestry limits.

The root role controls strict hierarchy validation and graph reachability,
not just rendering. `validateDAG: false` skips global DAG validation and local
graph-derived availability checks. Local ownership cycles are always rejected,
including cycles through `Lazy` or `Provider`. It never disables declaration
validation or effect compatibility on explicit sibling edges.

`Tools/report-validate-dag-escape-hatches.sh` runs in whichever of the
`fast-tests` and `macro-tests` jobs CI Plan selects (neither for an unlabeled
docs-only PR) and lists every container `validateDAG: false` site plus any
active `INNODI_DISABLE_BUILD_VALIDATION=1` environment override in the
workflow's step summary. The script is informational — set
`INNODI_ESCAPE_HATCH_FAIL=1` to flip it into a blocker for orgs that treat new
opt-outs as release blockers.

`Tools/measure-macro-performance.sh --enforce` keeps the single-PR
regression gate against the pinned `macro-performance-baseline.json`, and
`Tools/check-performance-trend.sh` runs alongside it in `macro-tests` to
compare against the rolling median of the `perf-history` branch (last 7
entries, minimum 5 comparable entries, 20% threshold, same-toolchain and
same-workload-version filters). In `CI`, only that exhaustive job runs them:
pull requests, whether labeled `release-validation` or selected by CI Plan,
run them with `--report-only`, while pushes to `main`, merge queue runs, and
manual dispatch enforce them. Both compare `min_ms`, while reports retain
every raw sample and dispersion statistics. The successful-expansion workload
is version 2; never relabel version-1 history or replace the pinned CI baseline
with a developer-machine result. The `CI` workflow reuses the gated
report for normal `main` history appends after CI Required succeeds;
`Perf History` is manual recovery. Missing/unreachable history or
fewer than five comparable entries is insufficient trend evidence, not a
measured trend pass.

`Tools/measure-macro-features.sh` separately measures assisted factory, large
multibinding, and mock generation. These independent v1 workloads are
report-only-unbaselined: verify successful generation and provenance, retain
all samples, and calibrate each on pinned CI before adding a timing gate.
Never feed their samples into the composite-v2 baseline/history.

### `@Provide`

- Public `@Provide` belongs only on a direct, plain, stored instance `var` in
  the same supported `@DIContainer` struct. Reject `let`, computed/observed
  properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone, and
  indirectly nested declarations. `_InnoDIProvideAccessor` is compiler-owned
  support and must never be attached by hand.
- Reject property wrappers, conditional/unknown attributes, setter access
  controls, and every source-written property-level global-actor attribute on
  providers, including `@MainActor`. Actor isolation comes from
  `@DIContainerRole(role: ContainerRole.local, mainActor: true)`; generated
  isolation attributes on declarations and accessors are internal support.
  Reject a complete provider
  member inside `#if` with `provide.conditional-declaration-unsupported`.
- Require exactly one `@Provide` per property. Reject opaque `some Protocol`
  provider types in favor of `any Protocol`, and reject implicitly unwrapped
  `T!` in favor of explicit `T` or `T?`. Deliberately forged combinations of
  the compiler-support accessor with another property wrapper may also receive
  Swift structural diagnostics alongside InnoDI's misuse diagnostic.
- `@Input`: external dependency; no `factory:`, `asyncFactory:`, `Type.self`,
  property initializer, or `with:`
- Generated `@Input` initializer parameters are eager `T` values and preserve
  ordinary `try` / `await` argument evaluation. Direct non-optional function
  spellings are detected and emitted as escaping parameters automatically.
  For a non-optional function type hidden behind a typealias, require literal
  `@Input(escaping: true)`. Reject the option outside `@Input` and for
  obvious nonfunction/optional-function shapes. Alias resolution is
  compiler-owned, so Swift may diagnose a conservatively accepted alias that
  is not actually a non-optional function.
- `.shared`: container-lifetime cached dependency; exactly one of `factory:`,
  `asyncFactory:`, `Type.self`, or a property initializer
- `.shared` with `initialization: .onDemand` and `asyncFactory:` constructs on
  the first read through `_InnoDIAsyncSharedCell`, which wraps a
  `DIAsyncScope`. The initializer starts nothing. The accessor is always
  `get async throws`, so use `providerEffect`, not `constructionEffect`,
  wherever the member acts as a provider. Such a container gains
  `closeAsyncProviders()`: `nonisolated(nonsending)`, or `@MainActor` with
  `mainActor: true`. The operation closure is `@Sendable`, or main-actor
  isolated in a `mainActor: true` container. Reserve the method name with
  `container.close-async-providers-name-conflict`.
- `.transient`: fresh dependency on every access; exactly one of `factory:`,
  `asyncFactory:`, `Type.self`, or a property initializer
- the declared property type determines storage shape: concrete nominal types
  use concrete storage and `any Protocol` types use existential storage

Sibling DI edges are intentionally syntax-bounded. Read them only from named
parameters on the root `factory:`/`asyncFactory:` closure literal, or from
`Type.self` plus a literal `with:` array containing only canonical direct-member
key paths spelled exactly `\Self.member`, such as `[\Self.config]`, or `[]`.
Reject named container, module-qualified, and typealias roots, nested
components, optional chaining, subscripts, and computed elements. `with:` is
valid only with `Type.self` and may target synchronous providers only. Do not
infer edges by
scanning a non-closure factory expression, property initializer, nested
closure, or arbitrary identifier. Non-closure factories and property
initializers are opaque zero-edge sources and must not reference sibling
container members; use a root closure parameter, or a qualified global/static
construction symbol when no DI edge is intended.

Factory effects are explicit. Validate effect compatibility on every explicit
sibling edge even when the container uses `validateDAG: false`.

### Deferred wrappers and sub-containers

- `Lazy<T>` creates a soft edge and stays non-`Sendable`.
- `Provider<T>` re-enters `.transient` access and stays non-`Sendable`.
- Ordinary on-demand cells also stay non-`Sendable`, even with Sendable
  payloads: factory captures require independent checking. Generated async
  dependency handles check both `Value: Sendable` and `@Sendable` factories.
- Public collection metadata preserves `AnyKeyPath & Sendable`; do not erase
  it to `AnyKeyPath` or reintroduce unchecked metadata conformance.
- `@SubContainer` adds ownership edges plus child override forwarding.
  Child inputs are synchronous in both child scopes; reject every asynchronous
  parent member, eager, on-demand, or transient, with
  `sub.async-parent-member`, including a `@SubContainerFactory(bindings:)`
  parent. Validation recovery keeps such a member's accessor synchronous
  whenever a sibling key path names it, so that diagnostic must stay terminal.
- Parent key paths in `@SubContainer(with:)` and on the `parent:` side of
  `bindings:` (including `@SubContainerFactory`) name one direct member as
  `\Self.member`. The macro rejects named roots with
  `sub.noncanonical-parent-key-path` and a fix-it from the validator, not the
  parser, so the rest of the container is still validated. The macro and build
  support reject nested components and `InnoDI-Migrate` blocks them; the graph
  CLI records no edge for them. Build support deliberately resolves named
  roots by member name so the compiler fix-it, not a plugin failure, reports
  them. Classify spellings only through `parentMemberKeyPathSpelling` in
  `InnoDICore`, and never call `filter` on a syntax collection when the result
  anchors a diagnostic, because it builds a modified tree.
- `swift run InnoDI-DeferredAliasScan --root .` lists every top-level
  `typealias` in the workspace that renames `Lazy<T>` or `Provider<T>`.
  InnoDI never resolves aliases: a factory parameter typed with one is a hard
  edge, and the generated call usually fails to type-check. The macro-level
  `provide.lazy-aliased` / `provide.provider-aliased` check only sees the
  source it is expanded with. A real compiler passes the attached declaration
  alone, so the check does not fire for file-scope aliases outside unit tests.
  Workspace build support records `deferred-alias.workspace-finding` warnings
  in the validation summary. Spell `Lazy<T>` and `Provider<T>` directly at
  factory parameters to obtain soft/provider edges.
  The `CI` workflow runs the scanner in whichever of the `fast-tests` and
  `macro-tests` jobs CI Plan selects and posts findings to the workflow's
  step summary plus a `deferred-aliases-report-fast-pr` or
  `deferred-aliases-report` artifact, respectively.

## Documentation Contract

- `README.md` is the English canonical README.
- `README.ko.md` and `Sources/InnoDI/InnoDI.docc/ko.lproj` must match the
  English structure and meaning. The Japanese, Simplified Chinese, German,
  Spanish, and Russian READMEs and `*.lproj` folders are notice pages frozen
  at 6.0.0; do not add content to them.
- `Tools/check-localized-readme-sync.sh` runs in strict mode whenever CI Plan
  selects the documentation contracts and in the release gate. It compares H2 and swift-fence counts of `README.ko.md` with
  `README.md` and of every `ko.lproj/*.md` article with its English
  counterpart in `Sources/InnoDI/InnoDI.docc`, requires every English article
  there to have a Korean counterpart, and requires the Korean README to keep
  its critical tokens. Any drift, or a notice page that stops linking
  its 6.0.0 translation, fails the build; `INNODI_README_SYNC_STRICT=0` demotes
  failures to warnings only for a soft-rollout window. The frozen `*.lproj`
  folders are never compared. Matching counts do not prove matching meaning,
  so mirror English prose edits in the same change.
- `CHANGELOG.md` is the single source for release notes and upgrade notes, and
  holds the latest-stable and development-train metadata. `RELEASING.md`
  defines the release process.
- If behavior changes, update docs in the same change.

## Review and release evidence

Freeze the revision/dirty baseline, module inventory, cross-feature risk matrix,
exclusions, and exit criteria before a comprehensive review. Cover source,
tests, public contracts, examples, and CI/release boundaries; exercise normal,
failure, cancellation, concurrency, retry/restoration, resource, observability,
and security paths where applicable. Reproduce suspected defects with passing
controls, distinguish fixture/environment failures, and close each matrix row
with fresh evidence, explicitly reused evidence, or a concrete limitation.
Report confirmed defects, unresolved candidates, optional improvements, and
unverified boundaries separately. A review alone does not authorize changes,
commits, pushes, or releases. A green suite is not proof of no remaining defects.

`RELEASING.md` defines the release contract. A version-promotion PR is not a
published release: verify its exact-SHA release workflow and immutable GitHub
Release before reporting publication. A PR run may check out a synthetic merge,
so verify its tree against the candidate and distinguish that from literal-SHA consumer
runs. Do not claim release readiness from local tests, skip/insufficient-history
statuses, or a green run for an older revision. Do not relax budgets or retry
unchanged candidates until green.
