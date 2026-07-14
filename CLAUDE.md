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
swift test
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
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
5. `InnoDI-DependencyGraph`
   - graph collection and Mermaid/DOT/ASCII rendering
6. `InnoDISwiftUI`
   - environment-bridge and feature-root integration helpers

### `@DIContainer`

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

All containers synthesize the overrides scaffolding unless the user already
declares a nested `Overrides` type, which suppresses generation.

`root` affects graph rendering only. `validateDAG: false` skips global DAG
validation plus the macro's local cycle and other graph-derived checks. It
never disables declaration validation or effect compatibility on explicit
sibling edges.

`Tools/report-validate-dag-escape-hatches.sh` runs on every PR and lists
every `@DIContainer(...validateDAG: false...)` site plus any active
`INNODI_DISABLE_BUILD_VALIDATION=1` environment override in the workflow's
step summary. The script is informational — set `INNODI_ESCAPE_HATCH_FAIL=1`
to flip it into a blocker for orgs that treat new opt-outs as release
blockers.

`Tools/measure-macro-performance.sh --enforce` keeps the single-PR
regression gate against the pinned `macro-performance-baseline.json`, and
`Tools/check-performance-trend.sh` runs alongside it on every PR to
compare against the rolling median of the `perf-history` branch (last 7
entries, 10% threshold, same-toolchain filter on by default). The
`Perf History` workflow appends one entry per push to `main`. The trend
script is a no-op when `perf-history` is empty or unreachable — fresh
forks pass without setup.

### `@Provide`

- Public `@Provide` belongs only on a direct, plain, stored instance `var` in
  the same supported `@DIContainer` struct. Reject `let`, computed/observed
  properties, `lazy`, `weak`, `unowned`, `static`/`class`, standalone, and
  indirectly nested declarations. `_InnoDIProvideAccessor` is compiler-owned
  support and must never be attached by hand.
- Reject property wrappers, conditional/unknown attributes, setter access
  controls, and every source-written property-level global-actor attribute on
  providers, including `@MainActor`. Actor isolation comes from
  `@DIContainer(mainActor: true)`; isolation attributes generated on provider
  declarations and accessors are internal support. Reject a complete provider
  member inside `#if` with `provide.conditional-declaration-unsupported`.
- Require exactly one `@Provide` per property. Reject opaque `some Protocol`
  provider types in favor of `any Protocol`, and reject implicitly unwrapped
  `T!` in favor of explicit `T` or `T?`. Deliberately forged combinations of
  the compiler-support accessor with another property wrapper may also receive
  Swift structural diagnostics alongside InnoDI's misuse diagnostic.
- `.input`: external dependency; no `factory:`, `asyncFactory:`, `Type.self`,
  property initializer, or `with:`
- Generated `.input` initializer parameters are eager `T` values and preserve
  ordinary `try` / `await` argument evaluation. Direct non-optional function
  spellings are detected and emitted as escaping parameters automatically.
  For a non-optional function type hidden behind a typealias, require literal
  `@Provide(.input, escaping: true)`. Reject the option outside `.input` and for
  obvious nonfunction/optional-function shapes. Alias resolution is
  compiler-owned, so Swift may diagnose a conservatively accepted alias that
  is not actually a non-optional function.
- `.shared`: container-lifetime cached dependency; exactly one of `factory:`,
  `asyncFactory:`, `Type.self`, or a property initializer
- `.transient`: fresh dependency on every access; exactly one of `factory:`,
  `asyncFactory:`, `Type.self`, or a property initializer
- concrete `.shared` and `.transient` storage requires `concrete: true`

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
- `@SubContainer` adds ownership edges plus child override forwarding.
- `swift run InnoDI-DeferredAliasScan --root .` lists every
  `typealias` in the workspace that renames `Lazy<T>` or `Provider<T>`.
  The macro plugin only detects same-file aliases; cross-file aliases
  silently behave as hard edges and disable cycle escape. The PR
  pipeline runs the scanner and posts findings to the workflow's step
  summary plus a `deferred-aliases-report` artifact.

## Documentation Contract

- `README.md` is the English canonical README.
- Localized README files and localized DocC mirrors must match the English structure and meaning.
- `Tools/check-localized-readme-sync.sh` runs in strict mode on every PR and the release gate; H2 or swift-fence drift fails the build.
- `RELEASING.md` is the single source for release notes and upgrade notes.
- If behavior changes, update docs in the same change.
