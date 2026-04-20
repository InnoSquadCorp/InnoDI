# InnoDI Roadmap

This document tracks follow-up work that is intentionally deferred from the
current release candidate. Items listed here came from open PR review feedback
or release hardening discussions and are not release blockers for `3.0.1`.

## Recently landed

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

With the override builder and the `Lazy<T>` cycle escape hatch shipped, the
remaining Top-tier UX improvements are re-ordered as:

1. `Provider<T>` — give call sites a factory handle when they need to pull
   multiple `.transient` instances per scope without retaining the
   container. Reuses the `ClosureParameterReference.type` plumbing added for
   `Lazy<T>` detection in Phase K.
2. `@SubContainer` — first-class nested containers for per-screen or
   per-request scopes, replacing today's convention of hand-wiring child
   containers through `.input` parameters.
3. Inter-container soft edges — populate `DependencyGraphEdge.isSoft` from
   the CLI `ContainerUsageCollector` once container-to-container references
   can be typed. The field is plumbed end-to-end today but the collector
   only emits hard edges.
4. `@Lazy` property wrapper — a lighter-weight alternative to `Lazy<T>` for
   deferring expensive `.shared` initialization. Pending real-world usage
   feedback on `Lazy<T>` before committing to the syntax.
5. Scope subdivision (request / session / scenario) — evaluate whether the
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
- Filter unresolved factory fix-it suggestions by declaration-order availability
  so diagnostics do not suggest names that would immediately trigger an
  unavailable-dependency error.
- Revisit `model.options.validate` handling for shared factory requirements to
  ensure runtime fallback and compile-time diagnostics remain aligned.

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
