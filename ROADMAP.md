# InnoDI Roadmap

This document tracks follow-up work that is intentionally deferred from the
current release candidate. Items listed here came from open PR review feedback
or release hardening discussions and are not release blockers for `3.0.1`.

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
