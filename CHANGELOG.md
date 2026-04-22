# Changelog

All notable changes to InnoDI should be recorded in this file.

The format is based on Keep a Changelog, adapted for the InnoDI release workflow in [RELEASING.md](RELEASING.md).

## Unreleased

### Added

- `Lazy<T>` escape hatch for breaking dependency cycles at the factory-parameter boundary. A factory parameter typed `Lazy<T>` is now classified as a *soft* dependency: it is excluded from both the per-container cycle detector (`container.dependency-cycle`) and the CLI's global `--validate-dag` check, while still being rendered in the dependency graph.
- `_LazyCell<T>` runtime class that backs the macro-generated `Lazy` wrappers so `struct` containers can forward-reference siblings without capturing `self`.
- `DependencyGraphEdge.isSoft` flag plus the `buildCycleDetectionAdjacency(nodes:edges:)` helper in `InnoDICore`, so macros and the CLI share one soft-edge contract.
- `Provider<T>` factory handle for pumping fresh `.transient` instances on demand without retaining the container. Factory parameters typed `Provider<T>` are classified as a new *provider edge*: excluded from cycle detection like `Lazy<T>`, but the validator requires the target member to have `.transient` scope (`provide.provider-non-transient-target`).
- `DependencyGraphEdge.isProvider` flag plus dotted renderer styling (Mermaid `==>`, DOT `style=dotted`, ASCII `~~>`) so provider edges stay visually distinct from `Lazy<T>` soft edges in the CLI graph.
- `@SubContainer(scope:with:)` macro + `SubContainerScope` enum for first-class nested containers. A parent declares a child property with an explicit `scope:` (`.shared` caches one child per parent lifetime, `.transient` rebuilds on every accessor read) and the macro auto-wires every parent `@Provide` member into the child's `.input` parameters. Each sub-container gains two `Overrides` slots — full replacement via `overrides.<name>` and a chain closure via `overrides.<name>Overrides` forwarded into the child's own convenience init.
- `DependencyGraphEdge.isOwnership` flag plus CLI ownership styling (Mermaid forces `owns: <member>` label on `-->`, DOT uses `style=bold, color="#1e3a8a"`, ASCII uses `#=>` with `:owns,<member>` suffix and a dedicated legend row). Ownership edges participate in cycle detection as hard edges because child construction runs at parent-init time.
- Phase M `sub.*` validator diagnostics — `sub.scope-required`, `sub.unknown-scope`, `sub.conflicts-with-provide`, `sub.unknown-parent-member`, `sub.shared-parent-must-not-be-transient`.
- Phase N-4 `provide.lazy-aliased` / `provide.provider-aliased` **warnings** — fire when a factory parameter uses a `typealias` that resolves to `Lazy<T>` / `Provider<T>`. The macro reads deferred-wrapper kinds from written syntax, so the aliased spelling silently falls through to a hard edge; the warning surfaces that fall-through at the parameter token.

### Changed

- Phase N-1: Split four large macro / build-support files into purpose-based modules with no public-API change. `DIContainerCodeGenerator.swift` (1,259 lines), `DIContainerValidator.swift` (904), `ValidationCoordinator.swift` (744), and `SwiftUIMacros.swift` (722) retain their original entry file and expand to nine new sibling files (init gen, overrides gen, sub-container gen, validation diagnostics, type checks, caching IO, POSIX locking, environment-bridge macro, feature-root macro). Tooling that references internal source paths should re-point at the new layout. All 349+ tests stay green.
- `@DIContainer(root:)` now acts as the graph renderer's entry set. When at least one root exists, Mermaid/DOT/ASCII output is pruned to the union of nodes and edges reachable from those roots. It still has no effect on DAG validation.
- `@DIContainer(validateDAG: false)` now disables the macro's graph-derived unresolved/declaration-order diagnostics in addition to opting the container out of global `--validate-dag`. Structural diagnostics remain enabled.
- `container.dependency-cycle` diagnostic message now suggests wrapping one factory parameter in `Lazy<T>` to break the cycle without restructuring.
- Mermaid, DOT, and ASCII renderers style soft edges distinctly: dashed arrows (`-.->`, `style=dashed`, `- ->`) with an ASCII legend that appears only when soft edges are present.
- `deduplicateEdges(_:)` in `InnoDICore` now follows a hard-wins rule when the same `(from, to, label)` triple is reported by multiple sites — a merged edge is soft only if *every* occurrence was soft, provider only if every occurrence was provider, and collapses to hard if sites disagree about the deferred-kind.
- ASCII legend extends to list `~~> provider (Provider<T>)` alongside the existing soft-edge clause when provider edges are present. A fourth legend row (`#=> ownership (@SubContainer)`) appears when ownership edges are present.
- `deduplicateEdges(_:)` now tracks `isOwnership` alongside `isSoft` / `isProvider` with the same hard-wins rule: a merged ownership edge survives only when every reporting site said ownership; deferred-kind disagreements still collapse to hard but leave the ownership flag untouched.
- `Overrides` / convenience init / `withOverrides` builder is now emitted for every `@DIContainer` unless a user-defined nested `Overrides` type suppresses it. Input-only containers therefore keep empty override scaffolding and support no-op child override forwarding.
- `@DIContainer` no longer exposes the unused `validate` parameter. Container-level validation configuration now uses `validateDAG` for DAG opt-out only.
- Unresolved factory-parameter and `with:` diagnostics now suppress rename/key-path fix-its when the closest normalized match is still unavailable at that declaration site due to declaration order.
- Repository release/process docs now center on tests, validation artifacts, and DocC generation; the legacy `Benchmarks/` suite and related workflows have been removed.
- `Lazy<T>` / `Provider<T>` no longer promise actor-boundary transport. Their public resolver surface is plain `() -> T`, conditional `Sendable` conformance has been removed, and accessor-generated wrappers now capture `self` directly so unsupported cross-actor use is rejected by Swift instead of being hidden behind `_LazyCell`.

## 3.0.1

### Changed

- Removed `swift-docc-plugin` from the main consumer package graph so SwiftPM users only resolve runtime/build dependencies needed to use InnoDI.
- Updated DocC generation to inject the DocC plugin only inside a temporary docs-only package during documentation builds.

## 3.0.0

### Added

- Docs entrypoint guidance for `README`, `Validation`, `PolicyBoundaries`, and `ModuleWideInitDetection`.
- Release governance documents for changelog, migration notes, and artifact schema expectations.
- OSS repository documents for licensing, contributing, security, and community conduct.
- Tag-based release workflow with release-gate validation checks and artifact uploads.
- Automated GitHub Release publication that uses the matching changelog section as the release body.

### Changed

- Promoted strict validation, semantic enforcement, and build-stage release contracts as the new major-version baseline for OSS consumers.
