# CI, dependency updates, and public operations

This is InnoDI's repository-local contract and the starting template for the
other InnoSquad public Swift packages. Reuse the interface and policy; inventory
each repository's manifests, consumers, platform/toolchain lanes, and publication
controls before adapting it. No central repository or credentials are required.

## Validation levels and changed paths

`CI` in `macro-tests.yml` creates **CI Plan** and **CI Required** for
`opened`, `synchronize`, and `reopened` PR events, adding/removing
`release-validation`, base-branch retargets (`edited` with `changes.base`), main
pushes, manual validation, and merge queue `checks_requested`. Drafts receive
the same path-selected validation as ready PRs. `ready_for_review` remains a
coordinator eligibility wake-up but no longer repeats expensive CI for an
unchanged revision. Other label changes and title/body edits create a native
metadata-only run with every job skipped. Its unique concurrency group cannot
cancel real validation, and its aggregate is named **CI Metadata Only**, so it
cannot publish a new **CI Required** verdict. There are no workflow-level path
filters that could leave a required check pending. Adding or removing
`release-validation` still replaces the previous plan for that PR.

Base retargets compare the new event base/head and reselect affected checks.
Re-running an old Actions run retains its original event SHA/ref, and a generic
manual dispatch is not bot PR proof. The bot coordinator still requires current
main/test-merge parents and exact run head/base association; stale or unverified
proof stays blocked. No automatic retarget/reopen/head mutation is introduced.

Metadata-only runs are never validation evidence. When selecting the latest
actual CI run, the bot and main-reuse policies authenticate newer metadata runs
against their immutable workflow blob and event merge parents, complete native
job/check inventories, skipped outcomes without steps, app/suite/URLs, and stable
attempt metadata. The event-bound run title alone cannot exempt a check. Missing,
pending, changed or unrecognized evidence blocks bot approval or falls back to
full main execution; a failed real CI run never becomes green. Older terminal
runs retain the existing historical attribution rules once a newer real
validation supersedes them. Hosted confirmation of the skipped-job inventory,
concurrency isolation and required-check identity is a deployment gate; local
transcript tests do not establish GitHub UI behavior.

| Level | Contract |
| --- | --- |
| Normal PR | Always run policy tests; select the affected fast jobs below. Source PRs retain strict in-process tests, public API, DAG, one representative example, compiled documentation, and DocC. |
| Main | Every unique validation contract, including coverage floors, the external consumer and strict-concurrency build contracts, TSAN/ASAN, Swift 6.2, Xcode 27/Swift 6.4, five Apple platforms, renamed path, all examples, and exact remote macro/plugin consumers. |
| `release-validation` PR | Every unique validation contract; label and unlabel events recalculate the current plan. No publication or history write. |
| Merge queue / manual CI | Every unique validation contract. Queue candidates are validated with the full merged tree. |
| Release candidate | Dispatch `Release Gate` on main with stable version, full lowercase SHA, and `publish=false` (default). Complete candidate gates, compatibility matrix, packaged DocC/notes/checksums, and exact-SHA consumers; **Candidate Required** must succeed. |
| Publication | A separate owner-approved dispatch with the same version/SHA and `publish=true`; revalidation and the existing `release` environment approval precede the public annotated tag. |

`Tools/ci-policy.py plan` compares the exact event base/head with Git's NUL-delimited
name/status stream. It uses the PR merge base, includes deleted paths and both
names of a rename/copy, and never downloads a truncated REST changed-file list.
Missing anchors, invalid events/labels/paths, or Git failures fail the plan. An
empty diff or an unknown path selects the full contract. Each job needs a
successful plan. Whenever the exhaustive coverage job is selected, the duplicate
fast job is unselected: the coverage pass uses the same strict compiler flags
and serialization with fewer skipped suites, and the exhaustive job also runs
every fast API, DAG, validation, and informational report command. Executable
tests pin the skip-set inclusion and complete fast-step inventory.
The policy job owns `test_public_api*.py` on Xcode 26.6; fast and exhaustive
CI skip only its duplicate Swift subprocess wrapper, and sanitizer runs skip
that non-instrumented compiler subprocess. The default local coverage command
and Release Gate retain the wrapper once. Swift 6.2 keeps its separate compiler
contract, and every applicable aggregate still requires the owner to succeed.
Consumer, TSAN/ASAN, platform, coverage-floor, performance, and exact-SHA gates remain
separate requirements; no unique check is removed.

The existing required policy job also runs `Tools/check-ci-workflows.py`; lint
does not allocate a separate runner. It downloads actionlint 1.7.12 for the host,
verifies a reviewed SHA-256 digest before extracting its executable, and checks
every workflow. Optional host-installed shellcheck/pyflakes integrations are
disabled so the result does not depend on the runner image. The unsupported
`concurrency.queue` diagnostic is narrowly exempted only after checking that
the three known coordinator writer queues retain their exact `max` values and
locations. A changed queue requires reviewing this exception. Download,
checksum and lint failures fail the policy job.

Every runner job has an explicit timeout. The previously unbounded exhaustive
CI pass now has 60 minutes; Examples and DocC have 30 minutes; lightweight
aggregates have 5 minutes, artifact/history transport 10 minutes, Pages deployment
15 minutes, and manual performance reconstruction 60 minutes. Existing dedicated
consumer/sanitizer/release budgets are retained. These initial bounds leave
headroom above the observed PR #50 exhaustive pass (22m04s), current-main pass
(17m13s), and 2–4 minute example/DocC jobs; they are not estimates of worst-case
cold runs. Revisit them with hosted distributions if legitimate runs approach
the limit. Timeout is a failure, never reusable success.

For a normal single-commit squash push to main, six jobs may reuse successful
PR verification: primary consumer contracts, sanitizers, Swift 6.2 compatibility,
Xcode 27 compatibility, Apple platform builds and path identity. The read-only
admission check requires an unambiguous merged same-repository PR, the latest
successful full CI run/attempt, exact native job/check/app/suite identities,
and the immutable tested merge commit with parents `[previous main, PR head]`.
Its complete Git tree must equal the new main tree, including workflow/action
and policy code. Source validation must have completed before the merge and
within 24 hours of both the merge and the current verification. No PR artifacts,
cache state or precomputed success flag is imported.

The plan retains every full logical requirement and carries explicit reuse
evidence separately. Only those six physical jobs may skip; `CI Required`
revalidates the identical source run/attempt/tree proof after the fresh jobs
finish. Missing, stale, ambiguous or inaccessible evidence during admission
selects ordinary full execution. Evidence revoked or changed after admission
fails the aggregate and blocks downstream publication/history work. Fork,
direct, multi-commit, forced, queue and manual runs remain full validation.

Policy validation, exhaustive coverage and main performance enforcement/trends,
examples, documentation contracts, DocC with main Pages artifacts, and the
exact-main-SHA remote consumer still run fresh. Performance history depends on
the successful aggregate and fresh exhaustive job, so intended physical skips
cannot suppress or bypass it. Its explicit status guard also requires a
successful plan and a non-cancelled run. The writer verifies its main checkout
SHA and consumes only this run's named macro-performance report artifact;
failure, missing artifacts and foreign run/repository overrides cannot supply
history evidence. Release Gate never consumes this reuse proof.

Cache observation commands are deliberately fail-closed. Invalid or unreadable
fingerprint/state/profile data fails the job; a `restored` observation failure
before validation can prevent subsequent tests from starting. A `report` failure
after validation can fail the job even when those tests already passed. The
workflow does not suppress these errors with `continue-on-error`. Cache hits,
product size/mtime observations and elapsed times are diagnostic evidence only;
they never substitute for successful current validation. A normal cache miss
is valid and continues through a cold build.

| Changed path | Selected PR validation (policy always runs) |
| --- | --- |
| Root manifest/lock, shared Xcode action, shared CI policy or unclassified build/release script | Full validation |
| Runtime/macro/plugin source | Fast contracts, representative example, documentation contracts, DocC |
| Tests / materialized consumer templates | Fast contracts; clean consumer fixtures select the Xcode 26.6 consumer contracts and both compatibility lanes; migration and mechanical fix-it tests select the full suite; remote fixture also selects remote proof |
| Live example source/manifest | All examples |
| README / ordinary Markdown | Compiled snippet, local link and localized README contracts |
| DocC catalogs / `.spi.yml` / DocC generator or lock | Documentation contracts and DocC |
| Dependabot only / issue and PR templates / LICENSE / SECURITY | Policy and public operations validation |
| Examples workflow | All examples |
| DocC/build or Pages workflow | DocC |
| Remote consumer workflow | Exact-revision remote macro/plugin proof |
| Release workflow | Full candidate-relevant read-only validation |
| Manual trace/cold benchmark/history workflow | Static policy and the executable shell/metadata negative contracts; optional timings remain manual diagnostics |
| CI orchestration workflow | All jobs (the orchestrator controls all validation) |

The final evaluator requires exactly one result for every declared dependency.
Selected jobs require fresh `success` or the final revalidated six-job reuse
proof. Only those proof-backed physical skips and explicitly unselected jobs
may be `skipped`.
Failure, cancellation, unknown/missing results, malformed plans, and unexpected
skips fail closed. `always()` prevents skipped `needs` propagation from suppressing
the aggregate. Reusable Examples has its own aggregate; each required child must
pass. Compatibility matrices use `fail-fast: false`, never `continue-on-error`.
A failed matrix child makes the required parent fail. PR validation uses no
release secrets, persisted checkout credentials, or write permissions. The
separate metadata-only Dependabot coordinator uses `pull_request_target` and
trusted main code; it never executes PR source. Public fork consumers resolve the exact fork
head through its public URL with normalized package identity; main retains the
exact-tip check, queue validation uses its temporary `head_ref`, and manual
branch validation uses the selected branch ref, including direct dispatch of
the reusable remote-consumer workflow without an explicit `branch_ref` input.
An explicit input must still match the selected SHA. Moving branches
can invalidate a run and require a fresh one.

Docs publication consumes the Pages artifact of a successful main push **CI**
run or verified actual Dependabot post-merge recovery via `workflow_run`; it never executes downloaded source from a PR. Ordinary manual runs still upload no Pages artifact. Before
deployment its originating SHA must still equal remote main, so a stale run or
rerun cannot roll documentation back. Main
performance history appends only after CI Required succeeds. These existing
post-validation writes are never part of candidate or PR validation.

## Cache identity and measurements

Root `Package.resolved` is ignored/untracked, so it is not a cache fingerprint.
`Tools/ci-cache.py` requires tracked, nonempty `Package.swift` and fixture profile
inputs and exact dependency pins. Keys include the actual complete Apple Swift
compiler version, Xcode version/build, macOS product/build, host architecture,
manifest and scratch-profile implementation. Unknown compiler profiles, empty
inputs and unpinned dependencies fail before restore. There are no broad fallback
restore prefixes, and old `v1` entries cannot match the `v2` keys.

The dependency cache contains only repository mirrors and downloaded prebuilts;
the root build stays cold. External consumer products use `shared-source` on
Swift 6.2/6.3 and `dag-plugin-source` on Swift 6.4, matching the fixture code.
Each profile keeps `pass`, `fail`, and `signature` scratch roots separate.
Macro-only prebuilt products are never restored into a source profile. This
change does not add shared scratch paths to strict-concurrency fixtures or change
fixture execution/assertions. The `Release Gate` workflow remains uncached.

Each cached lane reports its exact keys and cache-hit outcomes, elapsed restore
and validation observation windows, restored dependency-product counts and how
many retained their size/mtime afterward. Those observations support diagnosis;
a hit or unchanged product is not proof that a consumer passed, and elapsed
windows include surrounding steps. Use actual hosted step/suite durations for
before/after comparisons. A new fingerprint first produces a cold miss; no
percentage improvement is promised from the configuration alone.

## Release interface and boundaries

`Tools/validate-release-candidate.sh --version <version> --commit-sha <40-char-sha>`
is the local, network-free metadata interface. It creates no tag or Release.
`Tools/ci-policy.py require --jobs ...` is the common strict dependency evaluator
used by Candidate Required and reusable example validation.

The existing release workflow remains the single publication implementation.
Keep its annotated tag embedded-name/direct-commit/peeled-SHA checks, main ancestry
and untagged-tip policy, recoverable drafts, exact-tag Debug/Release consumers,
immutable Release verification, asset attestation, checksums and rerun recovery.
`publish=false` skips **stage-release**, **exact-tag-consumer**, and
**publish-release**. It can upload private workflow artifacts but cannot create
the SwiftPM-public tag, a draft Release, or a public Release. Approval must precede
the tag itself because SwiftPM consumers can resolve tags before GitHub Release
publication. Historical releases without this evaluator should use their original
recorded workflow for recovery; do not silently substitute new candidate code.

Repository settings are outside this change. The minimum proposed follow-up is
to make `CI Required` required for main/merge queue, retire obsolete per-job
required checks only after a successful new PR run, and verify the existing release
environment/ruleset contracts. A deletion/non-fast-forward ruleset alone does not
prove the absence of classic or other branch protections; a 403 is not proof of
absence. No protection, credentials, release settings, labels, or auto-merge are
changed by local validation.

## Dependabot contract

The config is JSON syntax inside `.yml` (JSON is a YAML subset), allowing the
repository guard to use Python's standard library. Validate it with a current
YAML parser and schema in addition to the executable repository guard.

| Ecosystem | Schedule (Asia/Seoul) | Open version PRs | Title/commit prefix | Group |
| --- | --- | --- | --- | --- |
| GitHub Actions | Monday 09:00 | 5 | `chore(ci)` | Minor/patch only, `actions-minor-patch` |
| Swift | Monday 09:30 | 3 | `chore(deps)` | Minor/patch only, `swift-minor-patch`, excluding SwiftSyntax |

Unmatched major upgrades and every SwiftSyntax upgrade remain individual reviewable
PRs. The normalized SwiftSyntax dependency name is
`github.com/swiftlang/swift-syntax`, not the bare package identity. Do not use
`prefix-development`, group `dependency-type`, or invented toolchain keys for Swift.
GitHub Actions uses `/`, preserving full commit-SHA pins and version comments.
Individual major and SwiftSyntax updates are eligible for the same guarded native
auto-merge as grouped updates. Every bot update must pass full CI. The coordinator
is prepared in standby; repository feature/protection/flag activation remains a
separate owner-approved settings step. See [activation and safety contract](dependabot-auto-merge.md).

Track root and the three current `Examples/*/Package.swift` manifests explicitly.
The examples currently use local path dependencies; listing them makes later
external dependencies visible without recursively modernizing test fixtures.
Do not include historical migration packages, `.fixture` templates, generated
DocC packages, scratch consumers, or intentionally pinned negative contracts.
`Tools/docc/Package.resolved` has no persistent companion manifest: update it
through the documented DocC generator in a coordinated maintainer PR.

SwiftSyntax stays exact `604.0.0`. A proposed bump must coordinate the root exact
requirement, DocC lock and injection regex, matching prebuilt consumer proof,
Swift 6.2 minimum, the Xcode 27 primary consumer toolchain, the Xcode 26.6
in-package lanes, and calibrated performance baselines. The public-operations
guard rejects partial manifest/lock/generator changes. Review toolchain selection
separately from low-risk dependency groups, and retain the `release-validation`
label until those checks pass.

SwiftSyntax 604.0.0 has a matching prebuilt on Swift 6.4 and none on Swift 6.3,
so Xcode 27 is the primary consumer toolchain. The exact-revision remote
consumer, the representative SampleApp example, and the cold build benchmark's
primary scenario run on the `xcode-27` runner. The remote consumer verifies an
isolated primary macro-only build with `Tools/cold-build-benchmark.sh` and
requires `swift_syntax_mode=prebuilt` there before running the combined
macro/plugin consumer; on Xcode 26.6 the same build reports `source`. The
in-package test, coverage, performance, sanitizer, platform, and documentation
lanes stay on Xcode 26.6: the root package builds SwiftSyntax from source on
every toolchain, and the performance baseline is calibrated there. A local
prebuilt observation is not evidence for the runner's lane.

Configured labels are `dependencies` plus `github-actions` or `swift`; both ecosystems
also request `release-validation`. At the implementation baseline only
`release-validation` exists among these labels. GitHub ignores missing custom
labels; creating shared ecosystem labels requires a separate approved settings
step. Version PR limits do not limit security-update PRs. Security updates and
alerts remain governed by existing repository settings.

Official references: [Dependabot options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference),
[Swift URL normalization](https://github.com/dependabot/dependabot-core/blob/main/swift/lib/dependabot/swift/url_helpers.rb),
[exact requirement handling](https://github.com/dependabot/dependabot-core/blob/main/swift/lib/dependabot/swift/native_requirement.rb).

## Public package operations

InnoDI already appears in the official
[SPI PackageList](https://github.com/SwiftPackageIndex/PackageList/blob/main/packages.json)
and has an [SPI listing](https://swiftpackageindex.com/InnoSquadCorp/InnoDI).
Registration is distinct from current-version indexing and documentation health.
The observed SPI page snapshot showed 5.1.0 while GitHub's current stable release
was 6.0.0; do not describe this as confirmed 6.0.0 indexing. On 2026-09-30,
GitHub Pages' API confirmed the configured homepage; HTTP 200 checks of its root
and `data/documentation/innodi/migrationguide.json` confirmed a published 6.0
migration guide without an unreleased marker. The successful main Docs run at
baseline `249e26703ab285092fd717896e48bba2d87a4533` is
[recorded here](https://github.com/InnoSquadCorp/InnoDI/actions/runs/36417345440). Do not submit duplicate
registration PRs.

`.spi.yml` uses SPI's supported `external_links.documentation` pointing to the
existing GitHub Pages DocC site. The canonical generator strips localized source
mirrors and restores catalogs excluded from ordinary Swift 6.4 builds. SPI does
not execute `Tools/generate-docc.sh`, so listing native `documentation_targets`
without proving SPI's build path would risk incomplete documentation. Keep public
targets `InnoDI`, `InnoDISwiftUI`, and `InnoDITesting` in the package inventory;
adopting native SPI generation later requires actual native target/archive checks.
No DocC plugin is added to the consumer manifest.

Validate the manifest through the [official SPI validator](https://swiftpackageindex.com/validate-spi-manifest)
or SPIManifest's current parser, and generate/inspect the existing DocC output.
See SPI's [common use cases](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Documentation.docc/CommonUseCases.md).
After an approved release, verify the indexed tag/SHA, reported compiler/platform
builds, documentation link and landing page. Record stale indexing as a separate
follow-up; a local build is not hosted-documentation evidence.

Keep the MIT 2026 InnoSquad license, existing private advisory reporting URL, and
latest-stable-major security support principle. SECURITY's stale `5.x` annotation
is aligned to current stable `6.x`; no older-line support or response-time promise
is introduced. The English README and its Korean mirror preserve installation,
requirements and structure; release/license badges and SPI links point to evidence.
The five translations frozen at 6.0.0 are notice pages that link the English
README and their 6.0.0 text.
CONTRIBUTING, issue forms, the PR template, `CHANGELOG.md` and RELEASING remain
the contribution, triage, review, release-note and release-process sources.
`CHANGELOG.md` is the single release-note source; no second changelog is created.

Repository description, homepage and topics were empty at the read-only baseline.
Propose a short package description, DocC homepage and relevant Swift/DI/macros
topics for owner approval; do not mutate external metadata during implementation.
External directory submissions, license changes, new SPI registration, support
policy changes, visibility and security settings also require separate decisions.
