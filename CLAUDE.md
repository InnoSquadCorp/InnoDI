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

All containers synthesize the overrides scaffolding unless the user already
declares a nested `Overrides` type, which suppresses generation.

`root` affects graph rendering only. `validateDAG: false` skips global DAG
validation plus the macro's local cycle and closure/`with:` graph-derived
checks, while raw-expression `factory:` and initializer references plus
structural diagnostics still remain active.

`Tools/report-validate-dag-escape-hatches.sh` runs on every PR and lists
every `@DIContainer(...validateDAG: false...)` site plus any active
`INNODI_DISABLE_BUILD_VALIDATION=1` environment override in the workflow's
step summary. The script is informational — set `INNODI_ESCAPE_HATCH_FAIL=1`
to flip it into a blocker for orgs that treat new opt-outs as release
blockers.

### `@Provide`

- `.input`: external dependency, no factory
- `.shared`: container-lifetime cached dependency
- `.transient`: fresh dependency on every access
- concrete `.shared` and `.transient` storage requires `concrete: true`

### Deferred wrappers and sub-containers

- `Lazy<T>` creates a soft edge and stays non-`Sendable`.
- `Provider<T>` re-enters `.transient` access and stays non-`Sendable`.
- `@SubContainer` adds ownership edges plus child override forwarding.

## Documentation Contract

- `README.md` is the English canonical README.
- Localized README files and localized DocC mirrors must match the English structure and meaning.
- `Tools/check-localized-readme-sync.sh` runs in strict mode on every PR and the release gate; H2 or swift-fence drift fails the build.
- `RELEASING.md` is the single source for release notes and upgrade notes.
- If behavior changes, update docs in the same change.
