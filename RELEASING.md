# Releasing InnoDI

This document defines how InnoDI is released. Version notes, the latest
stable version, and the current development train live in
[CHANGELOG.md](CHANGELOG.md).

`main` accumulates release work as independently green commits. During a
development train, keep the stable installation snippet on the latest stable
release and link its tagged documentation. Mark unreleased examples clearly
and provide a separate local-checkout installation for them. When the release
operator is ready to publish, land one final release-candidate commit that
renames `## Unreleased` in `CHANGELOG.md` to the exact stable version, updates
the latest-stable metadata there and the README installation references, and then dispatch the SHA-bound release workflow immediately. The
workflow validates that exact commit before it creates the immutable annotated
tag.

For the current 7.0 preparation branch, use the
[release-readiness checklist](docs/reviews/7.0.0-release-readiness.md) to review
the included API scope and final-head evidence. A preparation PR keeps the
unreleased banner and latest-stable metadata truthful. Only the final candidate
transition below changes those fields; opening or validating the PR does not
publish 7.0.0.

## Release Checklist

Before dispatching the `Release Gate` workflow:

1. Use an unprefixed stable SemVer such as `5.0.0`; prerelease/build metadata
   and a leading `v` are not accepted.
2. Run the main package test suite:
   - `swift test --no-parallel`
3. Run the strict-concurrency suite:
   - `swift test --no-parallel -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
   - Serialize independent test cases, as CI does, so synchronous compiler/CLI
     fixtures do not consume unrelated async tests' deadlines. Tests still run
     their internal concurrent tasks, cancellation and overlapping retry checks.
   - Run the release sanitizer suites from isolated scratch paths:
     `swift test --no-parallel --scratch-path .build/release-tsan --sanitize=thread -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)' --skip 'InnoDIMigrationCoreTests.InnoDIMigrationCoreTests/publicExecutableRunsFromFreshConsumer' --skip 'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'`
     and
     `swift test --no-parallel --scratch-path .build/release-asan --sanitize=address -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)' --skip 'InnoDIMigrationCoreTests.InnoDIMigrationCoreTests/publicExecutableRunsFromFreshConsumer' --skip 'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'`.
     The skipped fresh-consumer contracts spawn separate, non-instrumented
     Swift processes; the exhaustive and compatibility lanes run them instead.
4. Build, test, and where applicable run every example under strict
   concurrency with warnings as errors:
   - `Examples/SampleApp` (`swift build`, `swift test`, and `swift run --skip-build SampleApp`)
   - `Examples/SwiftUIExample` (`swift build` and `swift test`)
   - `Examples/PreviewInjectionExample` (`swift build` and `swift test`)
5. Run the global DAG check:
   - `swift run InnoDI-DependencyGraph --root . --validate-dag`
6. Run the repository contract guards:
   - `Tools/check-no-fatalerror-in-macros.sh`
   - `Tools/check-ci-validation-opt-out.sh`
   - `Tools/check-ci-action-pins.sh`
   - `Tools/check-docs-code-blocks.sh`
   - `Tools/check-docs-local-links.sh`
   - `Tools/check-localized-readme-sync.sh`
   - `Tools/check-public-api.py`
   - Refresh `Tools/public-api-baseline.json` with
     `Tools/check-public-api.py --update` only after reviewing an intentional
     API or normalization-schema change. The baseline covers all three public
     library products, including public macros and extensions on SwiftUI types.
7. Validate the Apple Privacy Manifests bundled with the embedded products:
   - `plutil -lint Sources/InnoDI/PrivacyInfo.xcprivacy`
   - `plutil -lint Sources/InnoDISwiftUI/PrivacyInfo.xcprivacy`
   - When the manifest is touched in this release, double-check that
     `NSPrivacyTracking`, `NSPrivacyTrackingDomains`,
     `NSPrivacyCollectedDataTypes`, and `NSPrivacyAccessedAPITypes` still
     match the actual SDK behavior — adding any Required Reason API to the
     runtime targets requires a corresponding manifest entry.
8. With Xcode 26.6 selected, build `InnoDISwiftUI` for the generic macOS, iOS,
   watchOS, tvOS, and visionOS destinations under complete strict concurrency,
   and reject warnings originating from an InnoDI source file.
9. Enforce the checked-in macro-performance baseline:
   - `Tools/measure-macro-performance.sh --enforce`
   - The 20% gate compares the fastest valid sample (`min_ms`) so shared-runner
     scheduling delay cannot masquerade as a macro regression. The report still
     records median, mean, maximum, standard deviation, and all raw samples for
     variance diagnosis. A real expansion slowdown raises every sample,
     including the lower envelope.
   - The baseline is hardware-sensitive. Refresh it only from a successful
     `Perf History` run on the same `macos-26` / Xcode 26.6 image used by CI;
     do not replace it with a developer-machine measurement.
   - Benchmark version 2 verifies successful container, override, child, and
     environment-bridge generation. Version 1 silently measured rejected child
     wiring; its timings are not comparable. The version-2 baseline comes from
     [Perf History run 36359716682](https://github.com/InnoSquadCorp/InnoDI/actions/runs/36359716682),
     candidate `1292253044e1d0e9d6678b9e716f61ec498dee51`, on
     `macos-26-arm64` image `20260907.0351.1`, Xcode 26.6 / Swift 6.3.3.
     All 30 samples from that first successful calibration are retained:
     minimum 227.409 ms, median 292.575 ms, standard deviation 90.979 ms.
     The unchanged 20% budget gives a 272.8908 ms minimum-sample limit; the
     substantial shared-runner variance is recorded, not filtered away.
     A version mismatch retains the measurement artifact and
     fails enforcement, even in report-only mode. Never relabel version 1
     samples as version 2 or relax the 20% threshold to obtain a green gate.
     Trend/history retain the benchmark version and compare like workloads only.
     Fewer than five version-2 history entries means insufficient trend evidence,
     not a measured trend pass. Keep version-1 history unchanged.
     CI still runs trend after a macro failure, without suppressing
     the original job failure.
   - Runtime trace timing is **optional diagnostic evidence, not a release
     gate**. The user approved this policy change on 2026-09-28 after review
     found scheduler-dependent overlap and measurement-definition limitations.
     Neither normal CI nor Release Gate runs the trace benchmark. InnoDI 6.0.0
     does not guarantee the checked-in trace nanosecond budgets.
   - To investigate trace costs, dispatch `Runtime Trace Diagnostics (non-release)`
     with a full `commit_sha`, or run `Tools/measure-runtime-trace-performance.sh`
     locally. The manual workflow requires a clean exact-SHA checkout and retains
     raw reports even when diagnostic checks fail. Invalid workloads and budget
     excess still return failure; they are not silently converted into passes.
     A missing, skipped, or cancelled measurement is not a performance pass.
     The existing budgets remain diagnostic reference values, not newly
     calibrated acceptance thresholds. See [trace measurement policy and
     limitations](docs/internal/trace-performance-6.0.md).
   - This exception changes only trace timing policy. Macro performance,
     correctness, coverage, concurrency, TSAN/ASAN, compatibility, platform,
     documentation, and consumer requirements remain in force. Removing this
     gate is not evidence of a performance fix or release readiness.
     This microbenchmark does not replace an actual consumer runtime pilot.
10. Generate DocC:
    - `Tools/generate-docc.sh`
    - package `.build/docc/InnoDI` with
      `Tools/package-release-docc.sh --source .build/docc/InnoDI --output <archive>`
      when manually checking reproducibility; the workflow performs this step
      twice-tested with normalized archive metadata
11. Decide whether any artifact or schema contract changed and update the
    contract notes below.
12. For public-discovery releases, confirm the pre-publication Swift Package
    Index inputs:
    - repository is public
    - `Package.swift` is at the root
    - `swift package dump-package` succeeds with the current Swift toolchain
    - On the release-candidate PR, apply the maintainer-only
      `release-validation` label. The label makes every subsequent PR update run
      the read-only exhaustive, sanitizer, Swift 6.2/6.4, Apple-platform, and
      renamed-checkout lanes before merge. Remove the label when the PR is no
      longer a release candidate. `workflow_dispatch` provides the same
      read-only validation for branches after this workflow entry point exists
      on the default branch. Neither path publishes a tag or performance history.
13. Complete the GitHub-side publication controls:
    - enable immutable releases for the repository
    - add an active branch ruleset with no bypass actors or exclusions that
      covers exactly `refs/heads/main` (or `refs/heads/*`) and prevents
      non-fast-forward updates and deletion while still allowing ordinary
      creation and fast-forward updates; store its numeric ID in the repository
      variable `RELEASE_MAIN_RULESET_ID`
    - add an active tag ruleset with no bypass actors or exclusions that covers
      stable SemVer tags, prevents update and deletion, and does not prevent
      creation; store its numeric ID in `RELEASE_TAG_RULESET_ID`
    - configure the `release` environment with exactly one required-reviewer
      rule, at least two distinct reviewer accounts, self-review prevention,
      disabled administrator bypass, and exactly one custom deployment branch
      policy named `main`; each reviewer must accept repository access before
      GitHub will retain them in the environment rule
    - store `RELEASE_ADMIN_TOKEN` only in that environment; use a fine-grained
      token limited to this repository with `Administration: read` and
      `Actions: read` so the workflow can verify immutable-release, ruleset,
      and environment policy without granting it an additional release-write
      credential; create it from a dedicated release-policy reader account,
      set a short expiry, then store it without copying it into repository or
      organization secrets:
      `gh secret set --repo InnoSquadCorp/InnoDI --env release RELEASE_ADMIN_TOKEN`
    - confirm `gh secret list --repo InnoSquadCorp/InnoDI --env release` shows
      `RELEASE_ADMIN_TOKEN`; GitHub never returns the value, only its presence
    The workflow fails closed before publication when the environment secret
    or either ruleset variable is missing, a policy does not match the contract,
    or repository release immutability is disabled. GitHub does not expose one
    transaction that combines tag comparison and draft publication. The tag
    ruleset closes that mutable-tag window, while the branch ruleset guarantees
    that a validated candidate remains on monotonic `main` history if `main`
    advances before publication.
14. In one final release-candidate commit:
    - rename the current `## Unreleased` section of `CHANGELOG.md` to the
      exact version
    - update `Latest stable public release` in `CHANGELOG.md` to the exact
      version
    - remove the matching `Current development train: <version> (unreleased)`
      line, or advance it to a later development train
    - update every installation reference in `README.md` and `README.ko.md` to
      the exact version; the other translations are frozen notice pages
    - replace the development-checkout installation and unreleased banner with
      the exact-version installation in both READMEs; update the linked
      stable documentation at the same time. The README installation contract
      test follows the development-train/latest-stable metadata above.
    - leave exactly one matching release-notes section in `CHANGELOG.md`
    - remove the `unreleased` marker next to the version in
      `Sources/InnoDI/InnoDI.docc/MigrationGuide.md` and the `미출시` marker in
      its Korean mirror; the candidate validator rejects either one
    - align English/Korean `Overview`, `OwnedContainers`, `DIContainer`, and
      `Provide` with the shipped API: no current-version candidate/unreleased
      claims, and both Overviews must name the exact stable version. The
      candidate validator checks these source articles; after publication also
      inspect their rendered DocC data from the deployed version, not a local
      build alone. Keep existing tags and previously published artifacts immutable.
    - for a 6.x release, record RFC 0006 as exactly `Accepted` in both the RFC
      document and RFC index, and for a 7.x release RFC 0008 and RFC 0009; the
      candidate validator rejects pending, duplicated, missing, or
      inconsistent status records
15. Push that final candidate to `main`, record its full 40-character commit
    SHA, and dispatch `Release Gate` from `main` with the exact
    version and SHA and `publish=false` first. Record the successful
    `Candidate Required` result, then request publication approval for that
    exact version/SHA. The approved dispatch uses `publish=true`; the existing
    `release` environment approval still gates the first public tag. Do not create or push the release tag manually, and do not
    rewrite or delete `main`. A normal fast-forward may advance `main`; the
    workflow rechecks that the exact candidate is still an ancestor of current
    remote `main`. It validates and packages that candidate before its
    least-privilege publication job creates the annotated tag and GitHub
    Release. If publication fails after the tag push, rerun only the failed
    jobs; the exact annotated tag is then the recovery anchor even if `main`
    later advances.
    The exact-revision consumer uses the same ancestry policy after preflight,
    while a new untagged dispatch still requires the current main tip. The
    standalone remote smoke workflow retains its independent main-tip policy.
16. After publication, verify the peeled remote tag SHA, GitHub Release notes,
    release immutability, the two checksum-covered assets, and `SHA256SUMS`.
    Add a fresh empty `## Unreleased` section and the next development-train
    metadata to `CHANGELOG.md` in a separate post-release commit. For public-discovery releases,
    confirm that the semantic-version tag is visible and that the existing
    [SPI listing](https://swiftpackageindex.com/InnoSquadCorp/InnoDI) indexes
    that exact tag/revision and links working documentation. InnoDI is already
    listed in SPI's PackageList; do not submit a duplicate registration PR.
    Track stale indexing separately from release publication. See
    [public operations](docs/automation-policy.md) for metadata and validation. Then evaluate external discovery PRs:
    - `matteocrippa/awesome-swift` for the compile-time DI category
    - the current leading SwiftUI awesome list only if the submitted entry
      focuses on `InnoDISwiftUI` helpers rather than core DI

## Release Notes Source

The manual, SHA-bound `Release Gate` workflow extracts the matching
`## <version>` section from [CHANGELOG.md](CHANGELOG.md) and uses it as the
GitHub Release body.
It rejects a candidate whose version, full commit SHA, latest-stable metadata,
localized README references, or release-notes section do not agree.

Each version section should include:

- highlights
- breaking or behavior changes
- upgrade actions

## Artifact and Schema Contracts

These artifacts are treated as release-quality contracts:

- validation metrics JSON artifact
- validation summary Markdown artifact
- dependency graph JSON document

Versioning rules:

- additive fields: minor schema increment or explicit release note
- changed semantics or removed fields: explicit schema bump plus upgrade note
- Markdown summaries do not carry a standalone numeric schema field; they follow the paired JSON artifact and the matching release section in `CHANGELOG.md`

Current tracked versions:

- `ValidationMetricsArtifact.currentVersion`: see [ValidationMetrics.swift](Sources/InnoDIBuildSupport/ValidationMetrics.swift)
- `sharedRunCacheVersion`: see [ValidationCoordinator.swift](Sources/InnoDIBuildSupport/ValidationCoordinator.swift)
- `GraphJSON.currentSchemaVersion`: see [JSONRenderer.swift](Sources/InnoDIDependencyGraphCore/Rendering/JSONRenderer.swift)

If artifact naming, schema shape, or coordinator cache salt changes, update
this document and the release-contract tests in the same change.

## Dependency Policy

InnoDI pins `swiftlang/swift-syntax` with `exact:`. SwiftPM uses a SwiftSyntax
prebuilt only when the resolved version matches the one the toolchain ships, so
the exact pin keeps the primary consumer toolchain on the prebuilt path. The
5.0.0 notes record the measured effect of moving the pin to `603.0.2`, and the
7.0.0 notes record moving it to `604.0.0` with Xcode 27 as the primary consumer
toolchain. The cost is that every package in a consumer graph must agree on
that exact version.

Re-evaluate the pin when a supported toolchain ships a prebuilt for a newer
swift-syntax release, or when a consumer reports a resolution conflict with
another macro package. Either move the exact pin to the version whose prebuilt
matches the primary consumer toolchain, or return to a range requirement if
SwiftPM starts matching prebuilts across a range. Record the result of
`Tools/cold-build-benchmark.sh --target consumer` and the consumer resolution
impact in the release notes of the version that changes the pin.

## Documentation Sync

Every release should leave these entrypoints consistent:

1. [README.md](README.md) and [README.ko.md](README.ko.md)
2. [Overview.md](Sources/InnoDI/InnoDI.docc/Overview.md) and its Korean mirror
3. [Validation.md](Sources/InnoDI/InnoDI.docc/Validation.md) and its Korean mirror
4. [PolicyBoundaries.md](Sources/InnoDI/InnoDI.docc/PolicyBoundaries.md) and its Korean mirror
5. [ModuleWideInitDetection.md](Sources/InnoDI/InnoDI.docc/ModuleWideInitDetection.md) and its Korean mirror
6. [ROADMAP.md](ROADMAP.md)

If a release changes user-facing validation, graph semantics, hierarchy
behavior, or SwiftUI integration, update those docs in the same change.

The repository keeps localized DocC Markdown mirrors for review and GitHub
reading. The generated DocC archive currently builds from the English base
catalog.

## Automated Release Artifacts

The release workflow publishes these assets to the GitHub Release:

- packaged DocC archive
- extracted release notes
- SHA-256 checksum manifest covering both files

Validation metrics and Markdown summaries remain release-quality contracts, but
they are produced as build and validation outputs rather than uploaded as
standalone release assets.
