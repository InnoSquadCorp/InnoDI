# InnoDI Roadmap

This document tracks the live roadmap after the 4.0.0 baseline and the
4.1.0 release-hardening pass.

## Shipped in 4.0.0

InnoDI 4.0.0 now treats the following capabilities as the stable baseline:

- Macro-generated DI containers with compile-time and build-time validation.
- Rooted graph rendering plus global DAG validation through `InnoDI-DependencyGraph`.
- `Overrides` scaffolding for every container unless a user-defined nested `Overrides` type suppresses generation.
- Deferred dependency wrappers:
  - `Lazy<T>` for soft-edge cycle escape hatches
  - `Provider<T>` for `.transient` re-entry
- Nested containers with `@SubContainer`, including ownership edges in graph output,
  explicit same-name wiring through exactly one of `with:` / `withNames:`,
  and child-to-parent label remapping through `bindings:`.
- Cross-module hierarchy support with `@DIComponent` and `@DIHierarchyRoot`.
- SwiftUI helpers through `InnoDISwiftUI`, including environment bridging and feature-root helpers.
- Validation artifacts, DocC generation, and a release workflow centered on `RELEASING.md`.

## Shipped in 4.1.0

InnoDI 4.1.0 hardens the 4.0.0 baseline without changing the public macro
surface:

- Validation coordinator locking now refuses unsafe filesystems by default
  (NFS mounts, SMB/CIFS, WebDAV, and FUSE-style filesystems) and documents the
  `INNODI_ALLOW_UNSAFE_LOCK=1` override plus `--scratch-path` recovery path.
- The coordinator lock now layers `open(O_CREAT | O_EXCL | O_RDWR)` with
  `flock(LOCK_EX | LOCK_NB)` on supported filesystems.
- Structured lock-timeout diagnostics, `--diagnose-lock`, and `--cache-stats`
  improve CI incident response.
- Malformed macro expansion paths no longer synthesize user-code
  `fatalError` accessors; terminal diagnostics plus empty expansion keep the
  failure at build time.
- PR and release gates both run the strict-concurrency suite and the
  macro-source `fatalError` allow-list guard.
- `@SubContainer(... withNames:)` now offers a `with:` Fix-it where Swift's
  peer-macro expansion rules allow the key-path form. RFC 0002 remains
  deferred for stacked peer-macro cases.

## Post-4.1.0 Priorities

### Review-Driven Improvement Backlog

The following backlog comes from the May 2026 whole-repository review and is
ordered by user-facing trust risk first.

1. Example and snippet compile fidelity
   - Status: partially addressed.
   - Problem: the dependency-graph sample under `Examples/SampleApp` was useful
     for CLI parsing, but it was not a standalone SwiftPM example and several
     concrete `@Provide(.shared, ...)` snippets omitted `concrete: true`.
   - Completed work:
     - `Examples/SampleApp` is now a runnable SwiftPM executable package.
     - The sample now uses explicit `concrete: true` where it demonstrates
       concrete storage.
     - The sample now demonstrates `@SubContainer(scope:with:)` for parent-owned
       child wiring instead of constructing the child as an ordinary dependency.
     - README and public doc-comment snippets now keep the concrete-storage
       examples aligned with the validation contract.
   - Completion criteria:
     - Add a CI/doc gate that compiles every fenced Swift example that is meant
       to be runnable.
     - Keep localized README snippets synchronized with the English canonical
       snippets whenever code changes, not only prose structure.

2. Build-plugin CPU and duplicate AST parsing
   - Status: addressed with a coordination patch; continue watching metrics.
   - Problem: the live DAG validation run was already shared across target-level
     build-plugin invocations, but source-signature collection happened before
     the live-run lock. On a cold cache, parallel target builds could all parse
     the same workspace and write the AST digest manifest concurrently. That can
     look like a CPU spike even when DAG validation itself only runs once.
   - Completed work:
     - Signature collection now uses a best-effort shared cache lock before
       reading or writing the AST digest manifest.
     - Concurrent coordinator tests now assert that two simultaneous requests
       perform only one AST reparse pass for the cold signature cache.
   - Completion criteria:
     - Watch `dag-validation-metrics.json` for high
       `signatureMetrics.astReparseCount` across many target invocations.
     - If CPU still spikes after this patch, inspect whether the Swift compiler
       is spending time in macro type-checking rather than InnoDI's coordinator.
       That is a separate macro-expansion/build-cost issue, not a DAG runner
       duplication issue.

3. Documentation-code contract
   - Status: open.
   - Problem: repository docs are comprehensive, but Markdown snippets are not
     all machine-verified. The risk is documentation drifting from macro
     diagnostics, especially around concrete storage, `with:` vs `withNames:`,
     and deferred wrappers.
   - Recommended next step:
     - Extend `Tools/record-macro-snapshots.sh` or add a dedicated
       `Tools/check-docs-code-blocks.sh` that extracts Swift fences marked as
       compileable fixtures and builds them under strict concurrency.
   - Completion criteria:
     - CI fails when canonical README or DocC snippets stop compiling.
     - Non-compilable illustrative snippets are explicitly marked so the gate
       skips them intentionally.

4. Macro dependency and consumer build cost
   - Status: measured, not refactored.
   - Problem: `InnoDI` intentionally depends on the macro target, and the macro
     target depends on SwiftSyntax. This is the expected cost of early
     validation, but it is still the main adoption tradeoff versus runtime-only
     tools such as Factory or Swinject.
   - Recommended next step:
     - Keep `Tools/measure-macro-performance.sh --enforce` in release gates.
     - Use the weekly consumer benchmark before considering package splitting
       or package traits. Do not split targets without measured consumer-build
       benefit.
   - Completion criteria:
     - Any package-surface split must include before/after consumer build time,
       macro benchmark numbers, and migration notes.

5. `withNames:` lifecycle
   - Status: deferred by RFC 0002.
   - Problem: the key-path form is better for rename safety, but stacked peer
     macro contexts still need `withNames:` as a compiler escape hatch.
   - Recommended next step:
     - Keep the current note diagnostic for non-stacked sites.
     - Revisit removal only after upstream Swift peer-macro behavior changes.
   - Completion criteria:
     - No removal plan until stacked `@SubContainer` + SwiftUI helper sites can
       use `with:` without circular peer-macro expansion failures.

1. Sub-container validation polish
   - `bindings:` now provides rename-safe child-to-parent label remapping.
     Future work should improve diagnostics for cross-module child input
     discovery, especially when build-support validation cannot see the child
     container.
   - Track the upstream Swift peer-macro limitation that keeps RFC 0002
     deferred for stacked `@SubContainer` + SwiftUI peer-macro sites.
2. Deferred and lifetime ergonomics
   - Evaluate whether `Lazy<T>` needs a lighter-weight surface such as a property-wrapper form, and whether the three built-in scopes need finer-grained lifetime variants for server-side or multi-window workloads.
3. CLI and validation polish
   - Add stronger `--help` coverage, more usage tests, and sharper diagnostics around graph collection, fix-its, and release artifacts.
4. Toolchain compatibility hardening
   - Keep SwiftSyntax, DocC, and build-plugin behavior stable across new Swift
     and Xcode toolchains without weakening the documented validation contract.
   - Continue narrowing the non-fatal Swift compiler-plugin JSON decode log
     tracked in `docs/internal/macro-plugin-json-investigation.md`.
5. Example and onboarding quality
   - Keep the SwiftUI examples, README set, and localized DocC aligned so new adopters can get to a working container and graph render quickly.
