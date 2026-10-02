# InnoDI: Apple validation plan for the adopted macro-first checkpoint

Prepared 2026-10-02 UTC. This is an execution plan and a local review proposal, not an Apple validation result.

## Decision and scope

The adopted feature checkpoint still needs Apple qualification. The existing Apple lanes already discover the added external consumer directories, compile the real macro plugin, and enforce strict concurrency. Two targeted additions are warranted:

1. Execute the package's in-process/runtime suites on Swift 6.2. Its existing compatibility job builds the test bundle but executes only `StrictConcurrencyBuildTests` and `ExternalConsumerContractTests`.
2. Put `makeOwnedWithOverrides` and owned synchronous `Lazy`/`Provider` forwarding behind the existing actual-plugin SwiftPM consumer matrix. These features currently have Linux portable-plugin coverage, but their consumer oracles are outside that discovery root.

The proposed patch closes those two gaps without adding or renaming jobs, changing CI selection, relaxing Ready/full proof, changing deployment floors, or updating the checked-in API baseline. It does not qualify the package until the Apple runs actually pass. It also does not claim to close every portable-only negative/compiler or performance boundary.

## Exact source identity

- Fresh fetched main: `dba4530494b148b24f6dfa382d70439bd1a8d513`
- Integrated feature checkpoint: tree `694e7fee6b91df1f328058477e8d7f91fb771c77`
- Proposal: `apple-ci-and-consumer-proposal.patch`, relative to the integrated checkout
- Proposal does not modify the live checkout. `proposed-tree/` contains only its changed files; `policy-validation-tree/` is an isolated static-policy test copy
- Applying the proposal changes the candidate tree. Record the resulting tree/commit and patch digest before Apple execution. The integrated tree above is not the identity of the candidate with this proposal applied
- No commits, pushes, dispatches, PRs, Mac/Codex tasks, Apple builds, or baseline updates were performed by this planning task

## Repository-supported toolchain matrix

These mappings are the repository's fail-closed contract, verified from `.github/actions/select-xcode/action.yml`; this planning task did not verify runner installation or vendor availability.

| Lane | Runner | Required selection and reported compiler | Existing coverage |
|---|---|---|---|
| Primary full CI/release | `macos-26` | Xcode `26.6`, `Apple Swift version 6.3` | Complete package suite split between coverage and external contracts, API, sanitizers, SwiftUI examples, platform builds |
| Minimum supported compiler | `macos-26` | Xcode `26.2`, `Apple Swift version 6.2` | Strict/external consumer execution and API semantics; proposal adds the remaining package suite |
| Release compatibility supplement | `macos-26` | Xcode `26.5`, `Apple Swift version 6.3` | Strict/external consumer contracts; keep this existing release scenario |
| Preview, not a substitute | `xcode-27` | Xcode `27*`, `Apple Swift version 6.4` | Strict/external consumer contracts and source-authored API baseline; preserve this lane |

`Package.swift` is Swift tools 6.2 and pins SwiftSyntax 604.0.0. Do not replace that pin or substitute Linux Swift 6.4 evidence for either supported Apple compiler. A cache hit, compiler-canary informational result, or an unexecuted test's successful compilation is not evidence of runtime success.

## Draft, full, Ready and release policy

- Ordinary PR selection is changed-path based. Draft status does not change `Tools/ci-policy.py` selection
- `release-validation` selects all logical gates. Main push, merge queue, and manual dispatch are full lanes. Adding/removing that label is a CI trigger; merely making a PR ready for review is not a trigger for this CI workflow
- New `Tools/` changes and orchestration edits already select exhaustive CI. External consumer paths select the consumer and supported/preview compatibility lanes automatically
- `CI Required` evaluates every planned result and fails closed on failed, missing, cancelled, or unexpectedly skipped jobs
- Full verification replaces `Fast PR contracts` with exhaustive release contracts. Do not turn the fast lane into sufficient evidence for full/Ready
- Dependabot Ready separately requires a non-draft, exact-head/base, mergeable, fully verified bot PR. Its exact job inventory and allowed skips are unchanged. Manual-PR Ready success only says the Dependabot coordinator does not apply; it is not a full-validation attestation or permission to merge
- Main's bounded exact-tree reuse keeps the same allowlist and exact-head/base/tree attribution. Its production CORE set now additionally requires `Run minimum-toolchain package contracts`. Dependabot proof likewise requires exactly one occurrence of that step. Neither predicate permits its failure or skip; no new reuse or skipped jobs are admitted
- Release Gate retains exact-candidate checks, the full compatibility matrix, and its separate publication approval. A successful local run or this plan does not authorize dispatch, publication, or changing PR state

## Proposed diff

Eleven files:

1. `.github/workflows/macro-tests.yml`: add strict, serialized package test execution to the Swift 6.2 job, skipping only the two separately executed consumer suites; preserve its log as `swift-62-package-contracts`
2. `.github/workflows/release.yml`: execute the identical package command only for the existing Xcode 26.2 release-compatibility scenario
3. `Tests/ExternalConsumerFixtures/pass/owned-overrides-deferred/Package.swift.fixture`
4. Its `Sources/OwnedPublicLibrary/OwnedPublicLibrary.swift.fixture`
5. Its `Sources/FixtureApp/FixtureApp.swift.fixture`
6. `Tools/tests/test_macro_first_apple_contracts.py`: additive regression contracts
7. `Tools/tests/fixtures/dependabot-full-ci.json`: record the two additional Swift 6.2 CI step names as successful requirements
8. `Tools/main-ci-reuse-policy.py`: require the new package step in the production Swift 6.2 CORE set
9. `Tools/dependabot-merge-policy.py`: require exactly one new package step in production proof; its existing status checks still require success
10. `Tools/tests/test_main_ci_reuse_policy.py`: reject missing, skipped, failed, cancelled, or duplicate new-step evidence
11. `Tools/tests/test_dependabot_merge_policy.py`: the same negative controls for Dependabot proof

Updating the transcript alone is insufficient: the production proof predicates must reject an otherwise successful historical job that never ran the new package step. This revision enforces that requirement without changing job IDs, selection, allowed skips, permissions, or the reuse allowlist.

The fixture uses authored `@DIContainer(generateOwned: true)` declarations and a separate public library/client module. It reuses the established public portable fixture's API shape, adding a forward `Lazy` reference to an on-demand member. It checks ordinary/override construction, public owner/view/type identity, async close behavior, and deferred reads/override seeds before and after close. It contains no manual macro expansion, substitute runtime, `Mutex`, availability uplift, registry, or service locator.

This is a focused cross-module API compilation and override-result smoke. The new integer-valued forwarding checks do not prove caching identity, fresh transient construction, allocation counts, or cache cardinality. Existing suites cover deeper lifetime/cardinality/concurrency semantics; do not attribute those results to this fixture. The portable fixture's throwing/cancelled builder preflight and all of its negative cases are not silently counted as this fixture's coverage.

## Apple execution: exact commands

Run only in an approved Apple environment. The commands below do not request or operate the user's computer. Use one isolated checkout/build directory per Xcode version, pinned to the same reviewed candidate. Prefer clean candidate checkouts; if testing a local patch before commit, archive the exact patch plus untracked-file content/digests and label the result a tree result, not a commit result.

### 1. Verify compiler and source before any build

For Xcode 26.2, then repeat with `XCODE_VERSION=26.6` and `EXPECTED_SWIFT='Apple Swift version 6.3'`. Also preserve Xcode 26.5's existing release compatibility run.

```bash
set -euo pipefail
export XCODE_VERSION=26.2
export EXPECTED_SWIFT='Apple Swift version 6.2'
export DEVELOPER_DIR="/Applications/Xcode_${XCODE_VERSION}.app/Contents/Developer"
# Set these to the approved candidate checkout and a NEW external evidence directory.
: "${ROOT:?exact candidate checkout required}"
: "${OUT:?new evidence directory outside the checkout required}"
cd "$ROOT"
test -d "$DEVELOPER_DIR"
mkdir -p "$OUT"
xcodebuild -version | tee "$OUT/xcode-version.txt"
swift --version | tee "$OUT/swift-version.txt"
test "$(head -n 1 "$OUT/xcode-version.txt")" = "Xcode $XCODE_VERSION"
grep -F "$EXPECTED_SWIFT" "$OUT/swift-version.txt"
xcrun --find swiftc > "$OUT/swiftc-path.txt"
xcrun --sdk macosx --show-sdk-path > "$OUT/macos-sdk-path.txt"
xcodebuild -showsdks > "$OUT/sdks.txt"
sw_vers > "$OUT/os-version.txt"
uname -a > "$OUT/host.txt"
git rev-parse HEAD HEAD^{tree} > "$OUT/source-identity.txt"
git status --porcelain=v1 --untracked-files=all > "$OUT/source-status.txt"
git diff --binary HEAD > "$OUT/local-tracked.patch"
shasum -a 256 Package.swift Tools/public-api-baseline.json > "$OUT/input-sha256.txt"
if [[ -f Package.resolved ]]; then
  shasum -a 256 Package.resolved >> "$OUT/input-sha256.txt"
  cp Package.resolved "$OUT/package-resolved-before.json"
  printf '%s\n' 'Package.resolved present before resolution' > "$OUT/lockfile-state-before.txt"
else
  printf '%s\n' 'Package.resolved absent before resolution' > "$OUT/lockfile-state-before.txt"
fi
# Qualification may not silently inherit a reduced fixture selection or validation opt-out.
test -z "${INNODI_EXTERNAL_FIXTURE:-}"
test -z "${INNODI_DISABLE_BUILD_VALIDATION:-}"
```

`DEVELOPER_DIR` chooses this shell's tools without changing the machine-wide Xcode selection. A missing or misidentified Xcode fails here; do not fall back. Keep identical CPU architecture across the two qualification runs, or explicitly record architecture differences.

### 2. Build and execute the whole package under strict diagnostics

For a standalone qualification run, these unfiltered commands are the clearest full-package contract:

```bash
swift build -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  2>&1 | tee "$OUT/package-build.log"
swift test --no-parallel \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  2>&1 | tee "$OUT/package-tests.log"
```

These include `InnoDISwiftUITests` and `InnoDITestingTests`, the macro and core suites, runtime scopes/owners, migration/fix-it consumers, strict consumer tests, and every external pass/fail fixture. Do not substitute a focused filter for this final result.

Existing CI intentionally splits the same requirements. On 26.6, use `Tools/run-coverage-gate.sh` plus the separate strict/external consumer steps; the coverage script skips only those two suites. The proposed 26.2 step is:

```bash
swift test --no-parallel \
  -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  --skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)' \
  2>&1 | tee "$OUT/swift-62-package-contracts.log"
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  --filter StrictConcurrencyBuildTests 2>&1 | tee "$OUT/strict-consumers.log"
swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  --filter ExternalConsumerContractTests 2>&1 | tee "$OUT/external-consumers.log"
```

After actual package resolution/build, capture the real lockfile if emitted. The inspected checkout has no `Package.resolved`; its absence must not abort preflight, and no synthetic lockfile should be manufactured.

```bash
if [[ -f Package.resolved ]]; then
  cp Package.resolved "$OUT/package-resolved-after.json"
  shasum -a 256 Package.resolved > "$OUT/lockfile-sha256-after.txt"
  printf '%s\n' 'Package.resolved present after actual resolution/build' > "$OUT/lockfile-state-after.txt"
else
  printf '%s\n' 'Package.resolved still absent after actual resolution/build' > "$OUT/lockfile-state-after.txt"
fi
```

Run either the unfiltered standalone sequence or the complete split sequence for the final qualification, not both merely to inflate test counts. The split commands do not skip the mechanical fix-it or migration executable cases.

New feature coverage to confirm in the actual suite logs: availability index/dependency order tests, typed prewarm tests, owned generated/compiler/runtime tests, `DIAsyncAdmissionTests`, `DIAsyncOwnerTests`, `DIAsyncScopeStartTests`, `DIAsyncScopeCancellationTests`, `DIAsyncScopeValueTests`, `DITraceOwnerIdentityTests`, `OnDemandReadyPathTests`, and the new real-plugin external fixture. Test compilation alone is insufficient.

For debugging the new fixture only, this is an exact narrow reproducer, not a full gate:

```bash
INNODI_EXTERNAL_FIXTURE=owned-overrides-deferred \
  swift test -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors \
  --filter ExternalConsumerContractTests/compilePassFixturesBuild
```

Never export that fixture selector for the full suite; the fail fixture enumerator would have no matching fixture and, more importantly, the full matrix must remain intact.

### 3. API capture and intentional-delta review without editing the baseline

```bash
python3 -B -m unittest discover -s Tools/tests -p 'test_public_api*.py' \
  2>&1 | tee "$OUT/public-api-checker-tests.log"
# Explicit alternate destination: this writes only the new evidence file.
Tools/check-public-api.py --baseline "$OUT/public-api-current.json" --update \
  2>&1 | tee "$OUT/public-api-capture.log"
# This must remain the real checked-in-baseline gate; a mismatch stays a failure.
Tools/check-public-api.py 2>&1 | tee "$OUT/public-api-gate.log"
```

The symbol-graph checker requires `InnoDI`, `InnoDISwiftUI`, and `InnoDITesting`. It preserves effects, isolation, mutability, defaults, alias semantics and relationship contracts across compiler rendering differences. New `ContainerInitializationOrder`, macro parameters, owner/admission/preparation types, and scope initialization/lifecycle surface are intentional API candidates, not an excuse to accept any diff.

The current feature checkpoint deliberately leaves the checked-in baseline unchanged. An Apple API mismatch is expected until the actual emitted delta is reviewed; classify it as **pending intentional API review**, never as passed. Capture the full diagnostic and candidate file even if a later gate stops. Compare the normalized `public-api-current.json` from 26.2 and 26.6, investigate every unexplained difference, and check both against the same reviewed candidate contract. Only a separately authorized, reviewed API baseline update should change `Tools/public-api-baseline.json`; then rerun the real gate on both toolchains. Compare the baseline digest before/after to ensure evidence collection did not modify it.

Generated consumer-specific methods do not all appear in the product modules' symbol graphs. That is why actual cross-module consumer compilation is required in addition to the baseline. None of this proves prebuilt binary drop-in compatibility.

### 4. Platform deployment-floor compilation

Declared floors: macOS 14, iOS 17, watchOS 10, tvOS 17, visionOS 1. Existing CI builds the `InnoDISwiftUI` scheme on all five generic platforms at Xcode 26.6, which covers its `InnoDI` dependency. It does not independently prove `InnoDITesting` on all five platforms.

For this feature qualification, run the following on both 26.2 and 26.6. First capture `xcodebuild -list -json` and verify that these package product schemes exist. An absent scheme is a blocker to resolve, not a reason to silently omit the product. The proposal intentionally does not widen the existing five-platform workflow while closing the narrower consumer/minimum-compiler gaps.

```bash
xcodebuild -list -json > "$OUT/package-schemes.json"
SOURCE_PREFIX="$(pwd -P)/Sources/"
for scheme in InnoDISwiftUI InnoDITesting; do
  for platform in macOS iOS watchOS tvOS visionOS; do
    case "$platform" in
      macOS) floor_setting=MACOSX_DEPLOYMENT_TARGET=14.0 ;;
      iOS) floor_setting=IPHONEOS_DEPLOYMENT_TARGET=17.0 ;;
      watchOS) floor_setting=WATCHOS_DEPLOYMENT_TARGET=10.0 ;;
      tvOS) floor_setting=TVOS_DEPLOYMENT_TARGET=17.0 ;;
      visionOS) floor_setting=XROS_DEPLOYMENT_TARGET=1.0 ;;
    esac
    log="$OUT/${scheme}-${platform}-floor-build.log"
    xcodebuild -quiet -scheme "$scheme" \
      -destination "generic/platform=$platform" \
      -derivedDataPath "$OUT/derived-$scheme-$platform" \
      -clonedSourcePackagesDirPath "$OUT/source-packages" \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      COMPILER_INDEX_STORE_ENABLE=NO SWIFT_STRICT_CONCURRENCY=complete \
      "$floor_setting" build 2>&1 | tee "$log"
    if awk -v prefix="$SOURCE_PREFIX" '
      index($0, prefix) && index($0, "warning:") { print; found = 1 }
      END { exit(found ? 0 : 1) }
    ' "$log"; then
      echo "InnoDI source warning in $scheme / $platform" >&2
      exit 1
    fi
    xcodebuild -scheme "$scheme" -destination "generic/platform=$platform" \
      -derivedDataPath "$OUT/derived-$scheme-$platform" \
      -clonedSourcePackagesDirPath "$OUT/source-packages" \
      "$floor_setting" -showBuildSettings \
      > "$OUT/${scheme}-${platform}-build-settings.txt"
  done
done
```

Preserve actual deployment-target settings/target triples and linked product platform/version evidence. This is a compile/link floor check, not execution on the oldest OS. Do not globally raise deployment targets to make tests compile.

### 5. Availability and actual minimum-OS runtime limits

`DITraceOwnerIdentityTests` has nine test functions individually annotated with `@available(macOS 15, iOS 18, watchOS 11, tvOS 18, visionOS 2, *)`; its `OwnerRecordingSink` helper uses `Synchronization.Mutex`. Its suite itself is not availability-annotated. Those nine tests cannot count as runtime coverage for any declared floor. Keep their annotations and verify they execute on the newer CI host, rather than simply being compiled or skipped.

`OnDemandReadyPathTests` uses the production wrappers and does not have the newer-OS annotation. Do not describe all new runtime tests as raised-availability tests.

A `macos-26` run proves execution on that runner's actual OS. `generic/platform=` only builds. To claim macOS 14 / iOS 17 runtime support for the adopted changes, an actual compatible floor runner/device/simulator must execute applicable runtime/consumer tests. Use `xcrun simctl list devices available -j` and `xcodebuild -showdestinations -scheme <verified-test-scheme>` to inventory actual devices; choose a verified UDID/OS, never a guessed simulator name. Use the discovered package test scheme and `xcodebuild test -destination id=<verified-UDID> -resultBundlePath <new-evidence-path>` for a supported test destination. If that Xcode cannot run on or target an available floor runtime, record the absence explicitly and arrange an approved compatible executor/device. There is no meaningful exact UDID or test-scheme string this Linux planning task can supply.

The current minimal patch does not provision older runtimes or add floor-safe substitutes for the nine Mutex-backed tests. Minimum-OS runtime coverage therefore remains a separate acceptance item, even if every proposed CI check passes. If equivalent floor-level tracing evidence is required, add an explicitly reviewed floor-compatible synchronization test fixture; do not mark a skipped newer-OS test as covered.

### 6. Preserve existing stronger gates and performance limits

On the primary Xcode 26.6 lane retain:

```bash
Tools/run-coverage-gate.sh
Tools/check-no-fatalerror-in-macros.sh
Tools/check-ci-validation-opt-out.sh
Tools/check-ci-action-pins.sh
python3 -B -m unittest discover -s Tools/tests
python3 Tools/check-public-operations.py
swift run InnoDI-DependencyGraph --root . --validate-dag
Tools/check-docs-code-blocks.sh
Tools/check-docs-local-links.sh
Tools/check-localized-readme-sync.sh
```

Keep existing thread/address sanitizer commands, separate scratch directories, exact-revision remote consumer, renamed-checkout contracts, exhaustive SwiftUI/preview examples, DocC, and release gates. Sanitizer suites' four subprocess exclusions are already independently covered by exhaustive/consumer jobs; do not broaden the exclusions. TSan/ASan and full Apple execution were not run here.

`Tools/measure-macro-performance.sh` remains report-only on PRs and enforced for main/queue/manual/release as defined today. `Tools/measure-macro-features.sh` is uncalibrated, report-only feature measurement. Do not add a timing gate or recalibrate a baseline from a single shared runner. Neither script establishes cold full-package/release-plugin improvement, minimum-OS correctness, or competitor superiority. The three rejected performance candidates remain rejected and absent from production sources.

`Tools/validate-owned-portable-plugin.sh` is explicitly a Swift 6.4/Linux narrow module check with `.so` outputs and a selected runtime source set. Do not run it unchanged on macOS and call it package qualification. The new SwiftPM fixture is the supported real-package route for the targeted positive contracts.

## Required evidence packet and acceptance

For each supported Apple compiler, preserve:

- Exact commit/tree, clean/dirty status, proposal digest, authored-source/manifest lockfile digests, Xcode build number, Swift version, SDK path, host OS and architecture
- Full build/test commands, exit statuses, complete untruncated logs, executed/skipped counts, and elapsed suite summaries. The new consumer's actual compile/run must succeed; wrong-diagnostic or crashing negative fixtures remain failures
- Primary fresh coverage `lcov.info`, `report.txt`, `summary.json`, `summary.md`, and `test-output.log`; unchanged coverage floors
- Strict/external consumer logs and cache fingerprints/profile. Dependency cache restoration is metadata, not validation
- Current normalized API JSON, unchanged prior baseline digest, API gate diagnostic, reviewed intentional delta, and a later passing gate after any approved baseline update
- Platform floor build logs/settings for both public product schemes; separate actual minimum-runtime results or an explicit coverage gap
- TSan/ASan, SwiftUI/InnoDITesting, examples, DAG, documentation, CI policy, exact-revision consumer and required aggregate results tied to the same candidate
- CI run/attempt/job/check URLs and exact head/base attribution for actual remote runs, if later authorized. No such run was started here

Acceptance is conjunctive: all required gates pass for the final candidate; intentional API changes are reviewed and encoded correctly; newly available tests are correctly separated from floor execution; outstanding minimum-runtime or portable-only contracts are disclosed. A local plan, passing static-policy test, successful compiler build, or a green informational canary cannot substitute for this packet.

## Validation performed on this proposal

- `git apply --check apple-ci-and-consumer-proposal.patch`: passed against the integrated checkout
- Existing CI/Dependabot Ready/main-reuse policy tests in an isolated copy: **122 passed**
- New static proposal contracts: **3 passed**
- Negative control against the original production predicates: both missing-step cases, plus Dependabot's duplicate-step case, fail the new regression assertions as expected. Corrected predicates reject all five invalid outcomes. See `required-step-negative-control.log`
- Both modified workflow files parsed as YAML
- CI action pin/permissions guard and build-validation opt-out guard: passed on the isolated proposed tree
- First static-policy run correctly detected the exact step inventory mismatch. The proposal updated the test transcript to include the two new required-success steps; the original failing log is retained as `policy-tests-before-inventory-fix.log`
- Apple compiler, SwiftPM consumer, runtime, sanitizer, API emission, deployment-floor and actionlint validation: **not run**. The new Swift fixture and exact-host execution costs are review proposals until those runs complete
