# 7.0 report remediation results

The reviewed starting point was PR #52 at
`064f1fc7fb8820d56181c17065be9b356845bdb5`. The supplied report was treated as
a set of hypotheses. Its original worktrees, TSan recordings, timing samples,
and numerical product scores were not available and are not adopted as results.
The [initial plan](../plans/report-remediation-7.0.md) was committed before the
corrections. This document records the local result before the next PR CI run.

## Per-claim disposition

“Fixed” below means the scoped regression passed locally. Apple-only execution
and complete matched-toolchain package builds remain CI requirements.

| Item | Disposition and boundary |
| --- | --- |
| P1-01a/b | Confirmed default-MainActor inference limitation. Explicit `@MainActor`, the role option, and `nonisolated struct` are documented and compiler-tested alternatives. An attached macro cannot infer the target's default-isolation setting; automatic inference is not claimed fixed. |
| P1-01c | The tested implicit/explicit MainActor mock constructors already work on MainActor. A separate explicit `nonisolated` protocol defect is fixed. The original exact reproducer remains unavailable. |
| P1-02 | Existing property-level `nonisolated(nonsending)` solves the qualified caller-isolation cases on Swift 6.2/6.3/6.4. An extra `resolveX()` API prototype was excluded. Shared async payloads and captures retain their Sendable requirements. |
| P1-03a | Removed unchecked legacy deferred transfer. Actual-plugin negative consumers now reject unsafe captures; supported exclusive transfer and actor-local usage pass. This is compiler-isolation evidence, not a TSan run. |
| P1-03b | Resolver cells bind before eager async startup. The previous premature-resolution trap and successful corrected consumer are preserved as separate evidence. |
| P1-04 | Ambiguous cross-file SwiftUI import access blocks writes and requests an explicit `--swiftui-import-access` choice. No guessed public/internal policy. |
| P1-05 | Existing adequate internal imports are preserved. Explicit/exported/public/package compiler controls cover the intended namespace and API visibility differences. |
| P1-06 | Attribute/modifier/comment boundaries and indentation are preserved; rewritten source is parsed before publication. Native Darwin atomic-write tests remain CI gates. |
| P1-07 | Collection metadata is declaration-local. Conditional duplicate identities and repeated members no longer feed a trapping unique-key dictionary. |
| P1-08 | Validation consumes the source bytes/trees whose signature was collected, including package/project syntax. Explicit external validators do not populate or reuse this snapshot-bound result cache. |
| P1-09 | Hosted feature-root overloads require explicit `FeatureRoot(..., hosted: true)` and source imports. Mere module availability cannot change generated behavior. The existing initializer remains; only two reviewed API symbols were added. |
| P1-10 | Kept collision-safe generated names. Documented and cross-module-tested explicit application typealiases for owner, view, preparation, and prewarm selections. Automatic natural-name aliases would shadow valid service types. |
| P1-11 | Caller cancellation and provider cancellation are distinct. Plan/owner preparation throws caller `CancellationError`; nonthrowing scope preparation returns actual provider state. Retry remains for failed/cancelled providers. |
| P1-12a/b/c | Policy hold: dependency automation, workflow credential exposure, and tag/release authority require a separate owner-approved settings/permission decision. No security settings or major-update preferences were changed. |
| P2-01 | Legacy on-demand teardown follows reverse dependency order, including dependency paths through eager nodes. Two generator regressions fail on the previous module and pass after correction. The external 99/100 trace frequency was not reproduced. |
| P2-02 | A joining reader forwards its current task priority to existing construction on runtimes supporting explicit escalation (Apple OS 26+). Linux baseline remained 9 under a priority-25 reader; the corrected test passes on 6.2/6.3/6.4. No OS QoS, latency, later dynamic escalation, or older-Apple-runtime improvement is claimed. |
| P2-03a | Documented that legacy close affects async on-demand storage only and is not an atomic owner-wide admission barrier. Eager tasks and application service shutdown remain outside it. |
| P2-03b | Reentry traps include the provider name. Twenty debug/release callback subprocess outcomes verify same-cell traps and other-cell success. |
| P2-04 | Unified the effective explicit/option MainActor policy across initialization, overrides, assisted factories, component/mount metadata, and close. Native async-on-demand capture execution still requires Apple CI. |
| P2-05 | Actual-plugin async collection input previously produced both the intended diagnostic and a raw async-key-path error. Recovery now preserves only the intended diagnostic. |
| P2-06a–h | Each mock lifetime, ownership, variadic, Self, generation, helper, and generic-handler claim is tracked in the [mock qualification](generate-mock-contract-qualification.md). Supported counterexamples are preserved; unsupported retained lifetimes receive explicit diagnostics. |
| P2-07 | Build-plugin JSON/text reports are no longer declared as distributable outputs. The generated Swift ordering barrier remains. Exact plugin-adapter Swift/Clang package controls no longer copy reports into resources; an actual Apple application artifact remains unverified. |
| P2-08a | Repeated conditional identities report unavailable compiler conditions before graph normalization. Branches are neither selected nor merged. This corrects the diagnostic, not support for configuration-dependent duplicate graphs. |
| P2-08b | Every conflicting declaration gets file/line/column. Two unconditional duplicates retain the definite duplicate label even alongside conditional declarations. Root mode retains its file-based identity boundary. |
| P2-09a | Forwarded only the documented validation environment allowlist. Exact adapter controls cover changes, unset values, unrelated-variable exclusion, and unchanged no-op behavior. |
| P2-09b | Signature locks immediately record PID/time/boot metadata so stale-owner handling can identify them. Deterministic lock/recovery tests pass. Legacy metadata-free crash windows and recovery-token crash behavior are not claimed eliminated. |
| P2-10a | Diagnostic caches bind exact bytes, displayed source paths, and result content. Trivia edits, moved checkouts, and mixed result/metadata publication cannot reuse stale positions. Location-free successes retain semantic reuse. |
| P2-10b | Declared in-package source-directory symlinks retain lexical logical paths while canonical containment and duplicate ownership stay enforced. External targets remain rejected. An actual SwiftPM symlink consumer is added for Apple CI. |
| P2-10c | The literal empty FAST_BUILD snippet compiles; adding a normal provider fails on all three compilers. Replacement marked examples and complete-declaration controls compile/run. Documentation explains why source analysis cannot select duplicate compiler branches. |
| P2-11a | External no-op/21-target timing estimates are unverified. No new consumer-build speed claim is made by this remediation series. |
| P2-11b | Repeated scope analysis/debug-tool cost remains a profiling question. Cache correctness, report outputs, and environment propagation were corrected without inventing performance evidence. |
| P2-11c | Prebuilt artifact distribution is excluded from this scope. No new external distribution service or access was introduced. |
| P2-12a | The external owned-size/build ratios remain unverified. Generated UTF-8 length, compiled binary footprint, and consumer compilation are separate quantities. |
| P2-12b | Added matched plain/owned async expansion workloads and an opt-in owned-API synthetic consumer scenario. Reports label the in-process driver and remain unbaselined; no release budget was changed. |
| P2-13a | `public import` is no longer confused with `@_exported import` in migration or target-aware graph lookup. Real compiler namespace controls pass. |
| P2-13b | Ambiguous import diagnostics name relevant modules using canonical attribute identities, separate from displayed labels. Unsupported `import macro` syntax is not claimed as a language feature. |
| P2-13c | Comment and indentation regressions are covered by exact-source rewrite/planning and compiler controls. |
| P2-13d | Recovery basenames use a bounded UTF-8 hint plus UUID instead of appending to an arbitrarily long filename. Added 194/249/246-byte write regressions; Darwin publication/rollback execution remains CI-only. |
| P2-14a | Combined the actual Quick Start declarations with the async override operation, reproduced failure on all three compilers, and made the service protocol/methods caller-isolated. The exact marked English/Korean snippets now compile and execute. |
| P2-14b | Reproduced Swift 6.4's default backend suppressing dump output despite successful macro consumer compilation. The inspection helper selects the native backend; 6.2/6.3/6.4 each emit 18 expansion blocks in the bounded consumer control. |
| P2-14c/d | Removed obsolete Korean root-option and 4.x overview guidance; stable 6.0 and unreleased 7.0 are distinguished. |
| P2-15 | All four Swift blocks in each OwnedContainers document now compile together in the documentation gate. The marked README Quick Start also executes the async override journey. README still has 2 marked blocks out of 17; remaining partial illustrations are not claimed executable coverage. |
| P2-16a | The supplied fork/proof interference attack is not dynamically verified. Existing policy regression tests run locally; no attack or policy mutation was performed. |
| P2-16b/c | Ruleset enforcement and trusted CI authority are separate policy decisions. No CODEOWNERS enforcement, bypass, review-count, workflow-permission, or merge-automation change is included. |

## Verification

- 112 core tests; 558 executed macro tests plus four named opt-in skips
  (Swift Testing reports 562 registrations). The Darwin-dependent
  `MechanicalFixItTests.uniqueBindingRepairBuildsAndGraphs` method remains a
  separate portable exclusion, not one of those four skips
- 67 async runtime tests on official Linux Swift 6.2, 6.3, and 6.4. A complex
  existing test expression needed explicit intermediate types for Swift 6.2;
  this changes no product behavior
- 83 cache/lock/snapshot tests; 27 migration planning/rewrite tests with real
  stub-module compiler controls; 50 integrated graph/identity tests
- Final actual-plugin portable suite: owned, prepared, legacy deferred,
  public-module, actor/override/lifetime consumers and 33 intended negatives
- Mock focused 61 tests, 195 expected compiler/runtime observations, additional
  fixture operations, and actual execution from the frozen plugin path
- Exact English/Korean README operation examples compiled and ran on each
  compiler. Native dump-script consumers passed on each compiler, and four
  extraction/failure contracts passed
- 216 portable Python tool/policy tests passed. Three existing alias-extraction
  tests require `xcrun` and a macOS SDK and remain Apple gates

Earlier failed attempts are preserved separately: invalid reproducer shapes,
qualification projections missing helpers, absent child compiler cache/PATH,
an artifact copy losing executable mode, and Apple-only test attempts on Linux
are not counted as product passes. The final plugin's bytes stayed unchanged
when its executable mode was restored and real invocation smoke tests passed.

## Release and measurement boundaries

Most portable consumers use one Swift-6.4/SwiftSyntax-604-built macro executable
with the named consumer compiler. This does not establish a complete package
build using each compiler's matching SwiftSyntax distribution. Concurrent mock
storage, Darwin atomic migration, SwiftUI hosting, legacy async-on-demand
runtime, minimum Apple OS execution, and the full public API gate still need
the corresponding hosted checks. No new user-Mac work is implied.

The earlier adopted predicate-order consumer-build result remains separately
scoped; rejected generic-cell and MainActor runtime experiments were not added.
This series makes no new runtime speed, heap-allocation, broad build-speed, or
competitor-ranking claim. It adds owned-workload visibility without changing
old measurement thresholds or treating driver output length as binary size.

This is PR preparation and validation, not merge, tag, release, or authorization
to change repository security policy. Passing the next PR CI alone does not
resolve separately held repository-policy and minimum-OS release decisions.

## Exact-head CI integration follow-up

The first published remediation head, `b2a89f5`, passed documentation, policy,
DocC, examples, and the remote consumer. Its complete runtime-test compilation
exposed an ordinary transient child builder still declared `@Sendable` while
capturing the newly checked deferred cell. The
[narrow resolver correction](transient-child-resolver-capture-2026-10-04.md)
preserves ordinary synchronous composition and MainActor isolation without
restoring unchecked transfer. Six actual-plugin wiring/isolation shapes,
existing child/eager runtime tests, escape negatives, the full portable suite
(now 35 intended negatives), and the full macro suite pass locally. The next
exact-head Apple run remains the integration gate; earlier passing jobs are not
substituted for it.
