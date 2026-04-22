# InnoDI Roadmap

This document tracks follow-up work that is intentionally deferred from the
current release candidate. Items listed here came from open PR review feedback
or release hardening discussions and are not release blockers for `3.0.1`.

## Recently landed

### Post-M hardening (Phase N)
- **N-1 (file splits)** — four large macro / build-support files split into
  purpose-based modules with no public-API change.
  `DIContainerCodeGenerator.swift` (1,259 lines),
  `DIContainerValidator.swift` (904), `ValidationCoordinator.swift` (744), and
  `SwiftUIMacros.swift` (722) are now distributed across 11 smaller focused
  files. Tests stay byte-identical.
- **N-3 (`sub.child-overrides-missing`)** — warning for same-file
  `@SubContainer` pointing at a child whose members are all `.input`. The
  generated `<name>Overrides` slot references `<ChildContainer>.Overrides`,
  which the child macro never synthesizes for input-only children. Detection
  is best-effort and silently skips cross-file children.
- **N-4 (`provide.lazy-aliased` / `provide.provider-aliased`)** — warnings for
  factory parameters spelled through a `typealias` that resolves to `Lazy<T>`
  / `Provider<T>`. Typealiased spellings silently fall through to hard-edge
  classification; these warnings surface the mismatch at the parameter token.
- **N-5 (docs / bindings edge cases)** — README / README.ko `root`
  vs `validateDAG` clarification table, explicit `@SubContainer(bindings:)`
  example, `MIGRATION.md` Phase N entry, `CHANGELOG.md` entries. Cross-module
  `sub.child-overrides-missing` plumbing stays as a follow-up (needs extra
  container scope flags in `ContainerSemanticBuildValidator`).

### Nested containers — `@SubContainer` (Phase M)
- `@DIContainer` types now declare owned child containers with
  `@SubContainer(scope: .shared | .transient, with: [\.parentMember])`.
  `.shared` children cache one instance per parent lifetime; `.transient`
  children rebuild on every accessor read by invoking a peer-stored
  closure that captures a `_lazySelfForSub = self` snapshot taken after
  every other parent storage slot is initialized.
- Every parent `@Provide` member is auto-forwarded into the child's
  `.input` parameters by name; `with:` restricts the forwarded set to a
  subset. Label mismatches surface as regular Swift compile errors on
  the generated call — the macro does not rewrite child labels.
- The `Overrides` builder gains two slots per sub-container member —
  full replacement (`<name>`) and a chain closure
  (`<name>Overrides`) forwarded into the child's own convenience init —
  so tests can swap children wholesale or tweak only specific
  `.shared` / `.transient` members inside the child.
- Five `sub.*` diagnostics lock the attribute contract:
  `sub.scope-required`, `sub.unknown-scope`, `sub.conflicts-with-provide`,
  `sub.unknown-parent-member`, `sub.shared-parent-must-not-be-transient`.
- The CLI graph renders parent → child ownership edges with their own
  style (Mermaid `owns: <member>` label, DOT `style=bold, color=#1e3a8a`,
  ASCII `#=>` + `:owns,<member>` suffix) and participates in cycle
  detection as a hard edge. `DependencyGraphEdge.isOwnership` is
  plumbed end-to-end through the collector + renderers.

### Transient factory handle — `Provider<T>` (Phase L)
- Factory parameters typed `Provider<T>` inject a handle that pumps a fresh
  `.transient` instance on every call, without the consumer having to retain
  the container. Detection mirrors the Phase K `Lazy<T>` heuristic (textual
  `Provider<T>` / `<Module>.Provider<T>`), and the macro reuses the same
  `_LazyCell` late-binding infrastructure, so implementation churn stays
  localized.
- A new `DependencyKind.provider` edge classification shares the cycle-
  detection exemption with `.soft` but is rendered with a distinct dotted
  style (Mermaid `==>`, DOT `style=dotted`, ASCII `~~>`). The validator
  additionally requires the target member to have `.transient` scope via
  `provide.provider-non-transient-target`.
- The macro now diagnoses direct `provider()` /
  `provider.callAsFunction()` use inside `.shared` construction so provider
  handles are only invoked after initialization completes, and the CLI
  `ContainerUsageCollector` now emits end-to-end deferred `isSoft` /
  `isProvider` edges for graph rendering and `--validate-dag`.

### Cycle escape hatch — `Lazy<T>` (Phase K)
- Factory parameters typed `Lazy<T>` now mark the corresponding dependency
  edge as *soft*. The per-container validator and the CLI `--validate-dag`
  gate both skip soft edges during cycle detection, and Mermaid/DOT/ASCII
  renderers draw them with dashed styling. Closes the Top-2 UX gap
  identified after Phase J.
- Backed at runtime by `Lazy<T>` (public) and `_LazyCell<T>` (internal box
  used by generated container inits), so struct containers can break cycles
  without reference-typed storage.
- The `container.dependency-cycle` diagnostic now suggests wrapping one
  factory parameter in `Lazy<T>` as a non-restructuring fix.

### Testing ergonomics — Overrides builder (Phase J)
- `@DIContainer` now emits a nested `struct Overrides`, a trailing-closure
  convenience `init(<inputs…>, _ applyOverrides:)`, and four
  `static withOverrides<T>` effect overloads for containers with any
  `.shared` / `.transient` member. Closes the Top-1 testing ergonomics gap
  identified in the post-PR-#17 comparison report.
- Input-only containers skip the scaffolding silently; user-declared
  `Overrides` types trigger the new `container.overrides-name-conflict`
  warning.

## Next priorities

With the override builder, `Lazy<T>`, `Provider<T>`, and
`@SubContainer` shipped, the remaining Top-tier UX improvements are:

1. Sub-container label remapping — when the child's `.input`
   parameter name differs from the parent member name, today's macro
   relies on Swift's compile error to surface the mismatch. A future
   iteration could rewrite labels based on `with: [\.parentName]`
   ordering so the wiring stays declarative even across renames.
2. `@Lazy` property wrapper — a lighter-weight alternative to `Lazy<T>` for
   deferring expensive `.shared` initialization. Pending real-world usage
   feedback on `Lazy<T>` before committing to the syntax.
3. Scope subdivision (request / session / scenario) — evaluate whether the
   three built-in scopes need finer-grained lifetime variants, especially for
   server-side and multi-window use.

## Post-3.0.1 Follow-ups

### Validation coordinator robustness
- Detect and recover stale lock files in
  `Sources/InnoDIBuildSupport/ValidationCoordinator.swift`.
- Add bounded retries and backoff around the coordinator lock acquisition loop
  so repeated cache misses fail predictably instead of retrying indefinitely.
- Replace the synchronous `Thread.sleep` polling path with an async wait model if
  the coordinator API is migrated to Swift Concurrency.

### Macro validation and fix-it quality
- Keep declaration-order-aware fix-it suggestions aligned with the
  `DependencyResolutionContext` rules so diagnostic candidates stay safe as new
  scopes or deferred-edge behaviors evolve.

### Example and test hygiene
- Revisit SwiftUI example `.task` / `.onDisappear` ownership boundaries for more
  explicit task lifecycle control.
- Deduplicate polling and waiting helpers used across tests where it improves
  clarity without obscuring intent.
- Add suite-level metadata tags/traits to larger Swift Testing suites once the
  project standardizes on a single categorization convention and syntax.

### CLI and documentation polish
- Add explicit `--help` coverage and usage tests for developer-facing tools.
- Improve docstring coverage for public and package-visible types involved in
  validation, semantic resolution, and release automation.
- Keep style-only cleanups, such as idiomatic cast chains and shorthand mapping
  expressions, out of release-critical PRs unless they materially improve
  correctness.
