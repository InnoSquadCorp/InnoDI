# CI, dependency updates, and public operations

This is InnoDI's repository-local contract and the starting template for the
other InnoSquad public Swift packages. Reuse the interface and policy; inventory
each repository's manifests, consumers, platform/toolchain lanes, and publication
controls before adapting it. No central repository or credentials are required.

## Validation levels and changed paths

`CI` in `macro-tests.yml` always creates **CI Plan** and **CI Required** for
`opened`, `synchronize`, `reopened`, `labeled`, `unlabeled`, and `ready_for_review`
PR events, main pushes, manual validation, and merge queue `checks_requested`.
There are no workflow-level path filters that could leave a required check pending.

| Level | Contract |
| --- | --- |
| Normal PR | Always run policy tests; select the affected fast jobs below. Source PRs retain strict in-process tests, public API, DAG, one representative example, compiled documentation, and DocC. |
| Main | Every validation job, including coverage floors, the external consumer and strict-concurrency build contracts, TSAN/ASAN, Swift 6.2, Xcode 27/Swift 6.4, five Apple platforms, renamed path, all examples, and exact remote macro/plugin consumers. |
| `release-validation` PR | Every validation job; label and unlabel events recalculate the current plan. No publication or history write. |
| Merge queue / manual CI | Every validation job. Queue candidates are validated with the full merged tree. |
| Release candidate | Dispatch `Release Gate` on main with stable version, full lowercase SHA, and `publish=false` (default). Complete candidate gates, compatibility matrix, packaged DocC/notes/checksums, and exact-SHA consumers; **Candidate Required** must succeed. |
| Publication | A separate owner-approved dispatch with the same version/SHA and `publish=true`; revalidation and the existing `release` environment approval precede the public annotated tag. |

`Tools/ci-policy.py plan` compares the exact event base/head with Git's NUL-delimited
name/status stream. It uses the PR merge base, includes deleted paths and both
names of a rename/copy, and never downloads a truncated REST changed-file list.
Missing anchors, invalid events/labels/paths, or Git failures fail the plan. An
empty diff or an unknown path selects all jobs. Each job needs a successful plan.

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
Selected jobs require `success`; only explicitly unselected jobs may be `skipped`.
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
branch validation uses the selected branch ref. Moving branches
can invalidate a run and require a fresh one.

Docs publication consumes the Pages artifact of a successful main push **CI**
run or verified actual Dependabot post-merge recovery via `workflow_run`; it never executes downloaded source from a PR. Ordinary manual runs still upload no Pages artifact. Before
deployment its originating SHA must still equal remote main, so a stale run or
rerun cannot roll documentation back. Main
performance history appends only after CI Required succeeds. These existing
post-validation writes are never part of candidate or PR validation.

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
Swift 6.2 minimum, Xcode 26.6 primary, Xcode 27 validation, and calibrated
performance baselines. The public-operations guard rejects partial manifest/lock/
generator changes. Review toolchain selection separately from low-risk dependency
groups, and retain the `release-validation` label until those checks pass.
The exact-revision remote consumer now verifies an isolated primary macro-only
build with `Tools/cold-build-benchmark.sh` and requires `swift_syntax_mode=prebuilt`
on unchanged Xcode 26.6 before running the combined macro/plugin consumer. A
local Xcode 27 prebuilt observation is not evidence for that primary lane.

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
