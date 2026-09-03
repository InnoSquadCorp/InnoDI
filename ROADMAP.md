# InnoDI Roadmap

This document tracks the live roadmap after the 4.0.0 baseline, the 4.1.0
release-hardening pass, and the 4.2.0 wiring/observability simplification
release.

## Shipped in 4.0.0

InnoDI 4.0.0 now treats the following capabilities as the stable baseline:

- Macro-generated DI containers with compile-time and build-time validation.
- Rooted graph rendering plus global DAG validation through `InnoDI-DependencyGraph`.
- `Overrides` scaffolding for every container unless a user-defined nested `Overrides` type suppresses generation.
- Deferred dependency wrappers:
  - `Lazy<T>` for soft-edge cycle escape hatches
  - `Provider<T>` for `.transient` re-entry
- Nested containers with `@SubContainer`, including ownership edges in graph output,
  explicit same-name wiring through `with:`, and child-to-parent label
  remapping through `bindings:`.
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
- `@SubContainer(... withNames:)` remained supported in 4.1.0 while RFC 0002
  was evaluated for stacked peer-macro cases.

## Shipped in 4.2.0

InnoDI 4.2.0 closes the RFC 0002 wiring-simplification window opened in
4.1.0 and lands the observability work that hardens the build plugin for
multi-target SwiftPM integrations:

- `@SubContainer(withNames:)` has been removed from the public macro
  signature, parser, diagnostics, build-support hierarchy validation, examples,
  and runtime tests. Supported explicit wiring is now `with:` or `bindings:`.
  ([RFC 0002](docs/rfcs/0002-subcontainer-wiring-simplification.md) is now
  `Implemented`.)
- Direct `Lazy<T>` calls during `.shared` construction now produce
  `provide.lazy-eager-call`, matching the Provider eager-call guard and keeping
  soft edges from silently becoming eager runtime traps.
- SwiftUI stacked helper examples that previously needed the string escape
  hatch now split root helper construction into ordinary extension methods.
- The DAG validation plugin stores lock/cache state below SwiftPM's plugin work
  directory instead of `<package>/.build/innodi-dag-validation`, keeping the
  documented `--scratch-path` recovery route valid on unsafe package roots.
- The validation plugin now uses a package-level shared state directory across
  target-level plugin work directories, and the repository includes a
  multi-target SwiftPM integration fixture that verifies cache reuse.
- `Tools/check-docs-code-blocks.sh` now compiles marked Swift documentation
  snippets, and CI/release gates run it.
- `InnoDIValidationTools` scaffolds the optional prebuilt macOS validation
  plugin package and release artifact tooling for consumers that have measured
  source-tool compilation as their main build-cost bottleneck.
- Apple Privacy Manifests ship with both runtime products
  (`Sources/InnoDI/PrivacyInfo.xcprivacy` and
  `Sources/InnoDISwiftUI/PrivacyInfo.xcprivacy`) declaring no user tracking,
  no tracking domains, no collected data types, and no Required Reason API
  usage.
- A new `InnoDI-DeferredAliasScan` executable target enumerates workspace
  `typealias` declarations that rename `Lazy<T>` or `Provider<T>`. PR pipelines
  attach the scan output to the workflow step summary and upload a
  `deferred-aliases-report` artifact.
- A `perf-history` orphan branch records one macro-performance entry per push
  to `main`. `Tools/check-performance-trend.sh` runs alongside the pinned
  baseline gate to catch gradual under-threshold creep across PRs.
- Build-validation escape-hatch reporting (`@DIContainer(... validateDAG: false)`
  sites and `INNODI_DISABLE_BUILD_VALIDATION=1` overrides) appears in every PR's
  workflow step summary. Set `INNODI_ESCAPE_HATCH_FAIL=1` to escalate the
  report into a merge blocker.
- Per-module test coverage runs on every PR via `Tools/collect-coverage.sh`,
  producing lcov + JSON + Markdown rollups uploaded as a `coverage` artifact.
- Custom SwiftLint rules under `Tools/InnoDILintRules/` add a fourth
  validation layer that catches `@DIContainer(... validateDAG: false)` and
  `typealias = Lazy/Provider` patterns the macro plugin cannot see from a
  single declaration site.
- The Korean README and DocC mirror the English structure, the migration
  guide adds internal v1–v3 adopter sequencing, and DocC includes
  anti-pattern guidance plus an interactive getting-started tutorial.

## Shipped in 4.3.0

InnoDI 4.3.0 integrated SwiftUI feature-root helper generation into
`@SubContainer`:

- `featureRoot:` covers the common single-root form.
- `featureRoots:` covers default and aliased root helpers.
- `InnoDISwiftUI` no longer depends directly on `InnoDIMacros`.
- In 4.3.0, `@DIFeatureRoot` remained available only as a deprecated
  compatibility path.

The concrete-inference and macro-consolidation runway previously planned for
4.3 did not ship.

## 5.0 Contract-Hardening Train

[RFC 0005](docs/rfcs/0005-5.0-contract-hardening.md) defines the accepted
breaking train. The release priority is public-contract trust, in this order:

1. External SwiftPM compiler fixtures for public pass/fail behavior.
2. `@DIComponent`, MainActor, scope, effect, type, access-control, and empty
   container correctness.
3. Complete construction-edge collection and fail-closed conditional DI.
4. Target/module-scoped plugin analysis with crash-free resolution.
5. Module-qualified graph identity, JSON schema v2, and explicit CLI scope.
6. Public-command, platform, performance, branch, and pre-tag release gates.
7. Migration tooling and the accepted 5.0 surface removals.

The deprecated `@DIFeatureRoot` compatibility macro has been removed on
`main`; feature-root helper generation now has one supported spelling through
`@SubContainer(featureRoot:)` or `featureRoots:`.

`main` is the 5.0 development line, while 4.3.0 remains the stable installation
version until the release-candidate matrix passes and the 5.0.0 tag is created.
Each implementation step lands as an independently green commit.

### Feature freeze during hardening

The following proposals do not block 5.0 and will not be added merely because
the release is a major version:

- `@DIComponent` / `@DIContainer` macro consolidation;
- implicit `@DIHierarchyRoot` activation;
- `@DIEnvironmentBridge` removal;
- `@GenerateMock` GA promotion before its existing criteria pass;
- scoped TaskLocal overrides;
- prebuilt validator publication;
- a full provider/member graph;
- an unproven SwiftSyntax constraint relaxation.

RFC 0004 remains as design history for the broader API-simplification work.
RFC 0005 supersedes its `concrete:` inference/token implementation: 5.0 removes
the public argument and uses the declared property type as the storage-shape
contract. The remaining macro-consolidation candidates are deferred to a future
major release.

### Review-Driven Improvement Backlog

The following backlog comes from the May 2026 whole-repository review and is
ordered by user-facing trust risk first.

1. Example and snippet compile fidelity
   - Status: addressed for current canonical snippets; continue expanding
     machine-verified coverage.
   - Problem: the dependency-graph sample under `Examples/SampleApp` was useful
     for CLI parsing, but it was not a standalone SwiftPM example. The sample
     and several snippets also carried the pre-5.0 `concrete:` argument and
     needed migration to the declared-type storage contract.
   - Completed work:
     - `Examples/SampleApp` is now a runnable SwiftPM executable package.
     - The sample no longer uses `concrete:`. Concrete nominal property types
       demonstrate concrete storage, while `any Protocol` demonstrates
       existential storage.
     - The sample now demonstrates `@SubContainer(scope:with:)` for parent-owned
       child wiring instead of constructing the child as an ordinary dependency.
     - README and public doc-comment snippets now keep declared storage shapes
       aligned with the 5.0 validation and public-signature contract.
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
   - Status: addressed for marked snippets; continue expanding coverage.
   - Problem: repository docs are comprehensive, but Markdown snippets are not
     all machine-verified. The risk is documentation drifting from macro
     diagnostics, especially around declared storage shape, sub-container
     wiring, and deferred wrappers.
   - Completed work:
     - Added `Tools/check-docs-code-blocks.sh`.
     - Wired the script into PR and release gates.
     - Marked the canonical README minimum example as a compiled snippet.
   - Completion criteria:
     - CI fails when canonical README or DocC snippets stop compiling.
     - Non-compilable illustrative snippets are explicitly marked so the gate
       skips them intentionally.

4. Macro dependency and consumer build cost
   - Status: measured; benchmark infrastructure consolidated.
   - Problem: `InnoDI` intentionally depends on the macro target, and the macro
     target depends on SwiftSyntax. This is the expected cost of early
     validation, but it is still the main adoption tradeoff versus runtime-only
     tools such as Factory or Swinject.
   - Recommended next step:
     - Keep `Tools/measure-macro-performance.sh --enforce` in release gates.
     - Use the single weekly cold-build benchmark for both the root package and
       a 100-binding synthetic consumer before considering package splitting or
       package traits. Do not split targets without measured consumer-build
       benefit.
   - Completion criteria:
     - Any package-surface split must include before/after consumer build time,
       macro benchmark numbers, and migration notes.

5. `withNames:` lifecycle
   - Status: removed.
   - Problem: the string form duplicated `with:` semantics without rename
     safety and complicated diagnostics/build-support parsing.
   - Completed work:
     - Public macro signature, parser, diagnostics, examples, and tests now use
       `with:` / `bindings:` only.
     - Stacked SwiftUI helper examples use manual helper methods instead of a
       string escape hatch.
   - Completion criteria:
     - `rg 'withNames' Sources/ Examples/ Tests/` returns only intentional
       historical documentation references, not supported API or examples.

1. Sub-container validation polish
   - `bindings:` now provides rename-safe child-to-parent label remapping.
     Future work should improve diagnostics for cross-module child input
     discovery, especially when build-support validation cannot see the child
     container.
   - Keep stacked SwiftUI helper guidance explicit: use `with:` on the child
     container member and split helper construction into ordinary extension
     methods when peer macro ordering becomes fragile.
2. Deferred and lifetime ergonomics
   - Evaluate whether `Lazy<T>` needs a lighter-weight surface such as a property-wrapper form, and whether the three built-in scopes need finer-grained lifetime variants for server-side or multi-window workloads.
3. CLI and validation polish
   - Add stronger `--help` coverage, more usage tests, and sharper diagnostics around graph collection, fix-its, and release artifacts.
   - The unpublished prebuilt validation-tools scaffold was removed from the
     5.0 tree after measurement showed it did not reduce the macro-only
     consumer build floor. Reconsider a separate companion repository only
     after source/prebuilt parity and independent release operations can be
     continuously proven.
4. Toolchain compatibility hardening
   - Keep SwiftSyntax, DocC, and build-plugin behavior stable across new Swift
     and Xcode toolchains without weakening the documented validation contract.
   - Keep `Tools/public-api-baseline.json` aligned only through reviewed SemVer
     changes; PR and release workflows compare compiler-emitted symbol graphs
     for `InnoDI`, `InnoDISwiftUI`, and public SwiftUI extensions.
   - Continue narrowing the non-fatal Swift compiler-plugin JSON decode log
     tracked in `docs/internal/macro-plugin-json-investigation.md`.
5. Example and onboarding quality
   - Keep the SwiftUI examples, README set, and localized DocC aligned so new adopters can get to a working container and graph render quickly.

## 6.0 Preparation Train

[RFC 0006](docs/rfcs/0006-assisted-subgraphs-and-container-roles.md) defines
the Draft direction for 6.0: child-owned assisted factories, separate input and
provider-lifetime declarations, and explicit container roles. The 5.2.x train
is limited to reversible groundwork while the RFC remains Draft.

Delivery order:

1. Add graph explainability and migration reporting on 5.x. The 5.2 train now
   includes `--why`, `--dependents`, `--unused`, schema-v2 `--diff`, and the
   source-free schema-v1 `InnoDI-Migrate --report` inventory.
2. Prototype child-owned assisted factories without removing stable 5.x APIs.
   An underscored SPI probe now partitions existing `.input` members into
   factory-captured static values and call-time assisted values, with a
   cross-module fixture proving per-child shared-storage isolation. Its source
   and generated names remain explicitly outside the stable contract.
3. Validate InnoSample, Mulbyul, and BlPia adoption against exact revisions.
4. Accept and freeze the RFC only after diagnostics, graph schema, migration,
   strict-concurrency, consumer, and macro-performance gates pass.
5. Remove superseded declarations and publish graph JSON v3 in 6.0.0.

The read-only static inventory for step 3 is now recorded in RFC 0006 against
fetched `origin/main` SHAs: InnoSample and Mulbyul are clean on their pinned
5.1.0 source, while BlPia is blocked at its 3.0.1-to-5.x migration boundary by
seven ownership-ambiguous legacy `concrete:` sites. This does not mark the
runtime pilots complete; exact experimental-revision builds and per-child
lifetime assertions remain required.

The train does not add runtime registration, an `@Injected` service locator,
or arbitrary global lifetime scopes. `@GenerateMock` and scoped task-local
overrides retain their independent promotion gates.

## Experimental Features & Promotion Criteria

InnoDI ships some surfaces as **experimental** before promoting them to the
release-frozen public API. Experimental surfaces remain opt-in, may change
generated-code shape between minor releases, and are documented as such in
their own docstrings. This section is the single registry of which surfaces
are experimental, where they sit in the rollout pipeline, and what has to be
true before the next minor release can promote them.

### Pipeline phases

| Phase | Meaning |
|---|---|
| `skeleton` | Macro/runtime stub exists; not enabled in any example or stable test. |
| `stage-2` | Functional opt-in drop; at least one example or runtime test exercises it; generated shape may still change. |
| `pre-GA` | Behavior frozen on `main`; only doc, diagnostic, and naming polish remain; promotion candidate for the next minor. |
| `GA` | Public API; SemVer applies to behavior and to generated symbol shape. |

### Active experimental surfaces

| Surface | RFC | Phase | Target version | GA criteria |
|---|---|---|---|---|
| `@GenerateMock` | [RFC 0001](docs/rfcs/0001-macro-mock-generation.md) | `stage-2` | TBD after GA criteria | All five criteria below must hold simultaneously. |
| Scoped task-local overrides | [RFC 0003](docs/rfcs/0003-scoped-task-local-overrides.md) | `skeleton` (Draft RFC) | 5.x or later | RFC must move from Draft to Accepted with all open questions answered before a `skeleton` implementation lands. |

### GA criteria for experimental macros

A macro can be promoted from `stage-2` to `GA` only when **all** of the
following hold on `main`:

1. **RFC open questions resolved.** The RFC's `## Open questions` section is
   empty or every remaining bullet is explicitly marked `Out-of-scope for GA`.
2. **Snapshot coverage.** Every supported variant (sync, async, throws,
   actor-isolated, generic, overloaded, associated-type-bound where the RFC
   says it is in scope) is covered by a macro snapshot test, and snapshot
   diffs from the previous minor are reviewed and intentional.
3. **Strict-concurrency clean.** The macro's generated code compiles under
   `-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` in the
   PR gate without emitting warnings.
4. **Adopter signal.** At least two real-world adopters (internal or
   external) have reported usage on the `stage-2` drop without naming-shape
   blockers, captured as references in the RFC.
5. **Promotion PR.** A maintainer opens a PR that flips the docstring from
   "Experimental" to the stable description, removes the experimental marker
   from the ROADMAP table, and bumps the relevant minor in `RELEASING.md`.
   The PR sits open for a 7-day cooldown before merge so existing adopters
   can object.

If a criterion is contested for a specific surface, the maintainer documents
the deviation in the RFC's `## Implementation Status` section rather than
silently skipping the gate.

### Stability guarantees

- Experimental surfaces are not covered by SemVer for **generated symbol
  shape** (mock helper names, storage suffixes, override slot names). The
  *attribute* name is stable once the RFC is accepted.
- Promoting a surface to GA is itself a minor-version event; demoting a GA
  surface back to experimental is forbidden — once promoted, only deprecation
  with a written upgrade path is allowed.
- Out-of-scope-for-GA RFC bullets are tracked separately and may ship as
  follow-up surfaces with their own RFCs.
