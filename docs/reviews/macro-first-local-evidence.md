# Macro-first improvement: local evidence ledger

2026-10-02 scope correction: historical whole-macro/composite-v2/whole-driver results here cover the root/member-attribute in-process driver, not full compiler expansion or consumer-build benefit. See the [actual compiler and consumer follow-up](macro-first-performance-track-2026-10-02.ko.md).

Date: 2026-10-01. Baseline: `6725e08b6da5d2ceeda61ed795adca5fadda564c`.
Status: implementation checkpoints, not completion of the whole next-major track.
No release, remote publication, merge, platform change or compiler-floor increase
is implied. See [the plan](../plans/macro-first-next-major.md) for the accepted owner policy and remaining release gates.

## What has changed for a developer

1. Existing macro declarations use an indexed availability analysis. Authoring,
   generated storage and diagnostic behavior remain the same in Phase 1.
2. An explicit `initializationOrder: ContainerInitializationOrder.dependency`
   option lets an acyclic shared provider precede its hard dependencies in the
   source. Default declaration order remains unchanged; construction is still
   separated into synchronous and asynchronous stages. Parameters, overrides,
   deferred ownership and child mounting retain their original contracts.
3. Typed synchronous prewarming is being qualified: `container.prewarm(.service)`
   can reject unsupported selections at compile time and removes the unnecessary
   unsupported-key-path error. An initial additive API failed the small-container
   budget; the current typed-only experiment replaces the key-path method.
   Dynamic/generic key-path adapters incur an explicit migration cost.
   The generated token uses the compiler-reserved `_InnoDI` namespace to avoid
   capturing ordinary payload type names. Explicit type spelling is less elegant.

No additional user-authored registration graph or runtime service locator is
introduced. The user selected explicit `makeOwned`; opt-in generated owner/view
integration is now under test. Ordinary initializers remain lightweight.

## Toolchain and validation scope

Swift 6.4 release, x86_64 Linux, official Debian 13 distribution. SwiftSyntax
604.0.0 was resolved from its official source package. The package's Apple
support contract remains unchanged.

- The default Swift 6.4 build engine rejected the baseline with duplicate
  `InnoDIMacros` target names. The supported `--build-system native
  --disable-experimental-prebuilts` route built the real macro target. This is
  a local validation route, not a repository workflow change.
- The full package test command fails on existing Apple-only Darwin imports.
- A copied, reduced package runs the unchanged core/macro suites using source
  SwiftSyntax. It excludes Apple-dependent targets and `MechanicalFixItTests`,
  which depends on the full workspace/graph stack. That scope is not the full
  repository suite or supported-platform consumer qualification.
- Two ignored `FileManager.createFile` results in a test helper were changed to
  explicit `_ =` so the focused test harness can compile under Linux Foundation
  with warnings-as-errors. Production platform/runtime code was not shimmed.
- The attempted shortcut using bundled resilient SwiftSyntax modules failed on
  an existing exhaustive-switch warning; measurements use source-built modules.

| Checkpoint | Executed result | Important limit |
|---|---|---|
| Baseline real macro target | Strict concurrency + warnings-as-errors pass | Not the runtime product |
| Baseline focused suites | 536 tests pass | Initial test helper had Linux-only unused-result warnings |
| Phase 1 focused suites | 541 tests pass, 35 suites | Adds 2 core tests and 3 macro integration tests |
| Phase 1 oracle | All 4,681 declaration sequences pass | These are cases inside a test, not 4,681 test functions |
| Phase 2 focused suites | 575 tests pass, 39 suites, strict + warnings-as-errors | Apple build-validator/runtime fixtures not executed |
| Phase 2 real macro target | Strict + warnings-as-errors pass after shared-helper repair | Same native/source build route |
| Initial typed-prewarm candidate | 588 tests pass, 41 suites, strict | Natural token-name candidate subsequently rejected for hygiene |
| Reserved-prefix typed-prewarm candidate | 590 tests pass, 42 suites, strict | Additive surface then rejected on generation cost |
| Pure runtime owner/scopes, after review repair | 60 tests pass, 9 suites, strict | Exact Foundation-only production sources; not whole Apple runtime suite |
| Supported Apple Swift 6.2/6.3/6.4 matrix | Not run | Required before release |
| SwiftUI / Apple runtime / consumer binary and RSS | Not measured here | Portable owner correctness does not substitute |

Independent read-only architecture and code reviews were performed for the
index and ordering changes. No blocking findings remained after the ordering
repair. Typed-prewarm cost and owner generated integration qualification are in progress.
An independent source-only owner runtime review found an overbroad cancellation
admission pause; the implementation removed it. No further source blocker was
found in the reviewed runtime checkpoint. Executed tests are reported separately.

## Review-discovered repairs and test corrections

- Compact macro member indices, not sourceOrder (which includes unrelated and
  child declarations), drive availability. Duplicate-name recovery retains union
  semantics, and unknown names take precedence over invalid consumer indices.
- Availability never removes forward/deferred ownership-cycle edges.
- A new test initially used an illegal unmanaged stored property. It was changed
  to a static member, and the full focused suite reran successfully.
- The initial ordering qualifier calculation did not model legacy normalized
  `_storage_` references accurately under `validateDAG: false`. A shared, pure
  stable-order helper now supplies the same exact-edge construction order to
  code generation and qualifier prediction. Tests cover earlier, forward and
  moved-later targets, preserving normalization only in fallback resolution.
- Attached macros check enclosing nominal names; full-source preflight checks
  enclosing members. Two assertions wrongly expected attached-macro diagnostics
  for the latter. The assertions now respect this boundary, and dedicated
  build-validator fixtures were added for the supported Apple lane.
- A Swift compiler canary confirmed that a new natural nested `PrewarmProvider`
  enum can silently capture an external payload enum with the same spelling.
  The natural name/alias was removed, rather than merely documenting a
  silent behavior change. The reserved-prefix design is not a universal name-
  resolution proof for arbitrary user-authored compiler-reserved names.

## Performance results: keep the scopes separate

All samples below use identical generated workloads and the same toolchain per
comparison. They are before/after InnoDI experiments, not competitor benchmarks.
CPU model reported by the VM: Intel Xeon Platinum 8573C. This is a shared managed
VM, not the pinned Apple release runner. Raw samples, source/patch/binary hashes,
commands and copied test manifest are retained with the local evidence package.

### Focused availability index

Optimized, syntax-free benchmark: index construction plus all edge queries.
The baseline algorithm preserves the original repeated set materialization.
Each timed result contributes to an observable checksum. Baseline/candidate
order alternates within the same process. N=20/50/200 use 30 paired samples and
three warmups. This excludes syntax conversion, module boundaries, macro output
and Swift consumer compilation.

| Members | Shape | Edges | Baseline median ms | Index median ms |
|---:|---|---:|---:|---:|
| 20 | sparse | 51 | 0.11382 | 0.00437 |
| 20 | dense | 150 | 0.37036 | 0.00800 |
| 50 | sparse | 135 | 1.05525 | 0.01456 |
| 50 | dense | 943 | 6.22804 | 0.04366 |
| 200 | sparse | 549 | 15.50856 | 0.06250 |
| 200 | dense | 15,111 | 426.66611 | 0.62854 |
| 1,000 | sparse, exploratory | 2,766 | 450.94212 | 0.32610 |
| 1,000 | dense, exploratory | 380,456 | 59,034.07511 | 19.03457 |

The N=1,000 run has only five pairs and one warmup because the legacy dense
workload takes about a minute per pass. It is explicitly exploratory and does
not satisfy the plan's 30-sample publication gate. It does not replace the
required compiled-consumer scaling experiment. No release budget was changed.
The very large isolated ratios must not be described as application speedups.

### Whole-macro composite-v2

Debug in-process macro expansion, unchanged fixture. Three alternating blocks
per version, ten measured expansions per block after thirty warmups. The original
row-level resampling was too optimistic about within-block correlation. The
corrected table uses 10,000 paired chronological-block draws, seed 6725. With
only three blocks these are descriptive intervals, not population confidence
guarantees. The former 5% regression-gate pass claim is withdrawn.

| Comparison | Baseline median ms | Candidate median ms | Median ratio | Descriptive block interval |
|---|---:|---:|---:|---|
| Index only | 281.6155 | 277.1620 | 0.9842 | 0.9365–1.1565 |
| Index + ordering infrastructure, declaration default | 287.0630 | 287.7660 | 1.0024 | 0.9371–1.0504 |

Both local intervals fall within the predeclared 5% regression bound for this
fixture. Neither establishes a speedup. Cold builds, opt-in large-container
costs and supported Apple consumer measurements remain outstanding. The existing
composite fixture does not exercise on-demand prewarm generation, so a separate
versioned benchmark has been added for its latency and generated-syntax growth.

## Competitor evidence and reassessment discipline

The same balanced rubric from the initial report remains fixed: algorithms 10,
static graph 15, types/concurrency 10, lifetime/failure 10, runtime resources 10,
day-to-day DX 10, testing/overrides 10, SwiftUI 5, build iteration 5,
docs/migration 5, platform/maintenance 5, operational tooling 5.

The prior expert-judgment result was 7.5 overall, CS 7.7, DX 7.3. It was not a
runtime benchmark. This ledger does not inflate those totals using a microbench
ratio or the number of passing tests. A final reassessment must separately state:
implemented behavior, measured benefit, remaining source/migration cost,
unsupported-platform evidence and unmeasured competitor cells.

Factory, swift-dependencies, Needle and Swinject comparison scenarios and pinned
baseline versions are in the implementation plan. No head-to-head runtime,
cold-build, binary-size, allocation, memory or user-task study has run in this VM.
Typed-token selection and declaration-independent wiring show concrete API/DX
changes, but do not by themselves establish that InnoDI beats each alternative.
The explicit async owner policy is chosen; generated integration, performance
qualification, consumer migration and head-to-head measurements remain ongoing.
The whole breaking-change improvement track is not complete.

## Rejected intermediate prewarm design

The additive typed plus legacy-key-path candidate used a required-first overload
and a private dispatch helper. Actual whole-macro on-demand generation, with 30
samples per version, three alternating blocks of ten and thirty warmups/block:

| Providers | Baseline median ms | Additive median ms | Median ratio | 95% ratio interval | Generated UTF-8 bytes |
|---:|---:|---:|---:|---|---|
| 1 | 84.560876 | 99.563743 | 1.17742 | 1.11796–1.25151 | 3,535 → 4,014 |
| 10 | 300.521642 | 307.466582 | 1.02311 | 0.97751–1.05409 | 11,086 → 12,276 |

N=1 fails the predeclared 5% bound; N=10 is inconclusive. This is measured cost,
not a theoretical objection. Raw samples remain preserved. The current experiment
uses enum + one typed variadic without legacy scan/helper; it is not accepted
until the same workload is remeasured. Runtime selection cost, binary and
migration consequences remain separate measurements.

## Owner runtime review repair

An initial cancellation admission token paused every provider, including unrelated
cached values. Narrowing the token to selected IDs would still deny selected
ready values even though cancellation affects only running work. The repaired
runtime has no cancellation admission pause. Per-scope actor cancellation is the
linearization point, and a multi-selection call is not atomic. Close retains its
terminal all-provider barrier and shared-completion joining.

The deterministic regression holds a cancellation callback open while selected
ready values are read and unrelated idle work starts, running work completes, and
failed work retries. Those operations pass. Selected running work is cancelled
when its own transition is reached and needs explicit retry (generation +1).
The strict portable suite passes 60 tests in 9 suites after this repair. The old
61-test result included an incorrect global-pause assertion and is historical,
not the accepted contract. Generated callback integration remains a separate gate.

## Typed-only checkpoint and measurement limits

The typed-only candidate removes both the legacy runtime key-path scan and the
extra private dispatch helper. Against the same pinned baseline, generated
syntax is 3,535 → 3,467 bytes for one provider and 11,086 → 10,676 for ten.
These deterministic byte counts are confirmed; they are not linked binary size.

The 30-sample/version rerun observed median ratios 0.679 (one) and 0.958 (ten).
However, one-provider baseline block medians were 90.839, 145.733 and 132.471 ms,
so a “32% speedup” would overstate the evidence. Candidate block medians were
82.527, 126.772 and 81.683 ms. This shared-VM drift limits any general conclusion.

Timing rows within a block are correlated. The corrected descriptive resampling
unit is the **paired chronological block of ten expansions**, with only three
blocks/version, 10,000 draws and seed 6725. It yields the following intervals:

| Candidate | Providers | Ratio of observed medians | Descriptive block interval |
|---|---:|---:|---|
| Rejected additive | 1 | 1.1774 | 1.1329–1.3869 |
| Rejected additive | 10 | 1.0231 | 0.8981–1.0627 |
| Typed-only | 1 | 0.6792 | 0.6166–0.9700 |
| Typed-only | 10 | 0.9581 | 0.8856–1.0426 |

The earlier row-resampling intervals are retained in raw historical artifacts,
but these block-aware descriptions supersede them for interpretation. They are
not population-level 95% guarantees with three independent blocks. Typed-only
passes the defined local threshold in this run; general performance improvement
or absence of regressions has not been established. Migration remains breaking.

The 606-test / 45-suite strict checkpoint compiled and executed the generated
**owned declarations** with actual portable production runtime, plus negative
wrong-token/actor canaries. That first harness omitted legacy declarations for
owner positives; an independent review correctly identified this coverage gap.
Full legacy + owned coexistence checks are now being added for portable forms.
Legacy on-demand async storage imports Apple `os`, so its full coexistence lane
remains Apple-required; Linux owned-only evidence must not be broadened to it.
A pre-existing `Self.Value` nested-Overrides failure is separately reproduced,
not claimed as full-entrypoint Self support because the owned view rewrites it.

## Actual-plugin qualification and additional hygiene repair

The real `InnoDIMacros` plugin product was linked and loaded by Swift 6.4, using
unchanged public `InnoDI.swift` plus portable runtime source files. A real authored
consumer compiled and executed empty/sync/non-Sendable/MainActor/eager async,
forward-order, value override, escaped-copy close, borrowed-child and running
cancel/retry paths. This closes the earlier manual-AST coexistence gap for those
forms. It still excludes Apple's legacy async-on-demand cell and is not full
package or older-toolchain release qualification.

The manual AST harness initially reapplied generated MainActor attributes as
though they were authored attributes and rejected its own output. The actual
plugin disproved that suspected production defect. The harness now invokes the
roles with original source/context, preserving generated attributes on output.
The corrected checkpoint passed 609 focused tests in 46 suites.

An additional **real plugin** canary then caught a new type-identity defect:
inside `struct Same { struct Same {}; @Input var factory: () -> Self }`, rewriting
Self as the nominal name made the owned view expect `() -> Same.Same`. The repair
emits an outer compiler-owned `_InnoDIOwnedSelf = Self` alias only when required,
and refers to that witness in nested-view types. Factory expressions are not
rewritten. Ordinary declarations emit no extra alias, and the existing reserved-
prefix diagnostic rejects authored collisions. The same failing plugin canary
passes after repair. This is separate from the old shared `Self.Value` / nested
`Overrides` limitation; it does not claim that limitation has been fixed.

## Ready-cell optimization: rejected intermediate designs

The first direct ready fast path checked only tracing-off + ready. It passed
ordinary identity/concurrency tests, but a factory-capture destructor can reenter
while the first read is still unwinding after publishing ready. A subprocess
proved that this draft returned a value where the baseline trapped. It was
rejected. The fast path now also requires `activeCallers.isEmpty` under the same
condition lock; active readers retain the original guarded path.

The next guarded draft avoided thread lookup but added a lock/unlock pair on cold
misses. Its 20-node local comparison improved warm batch mean (251 → 116 ns) while
worsening cold graph lifecycle (20.1 → 24.8 µs) and first resolution (9.2 → 12.8 µs).
It is **not adopted** on warm numbers alone. A conservative single-lock candidate
preserves the original Thread.current-before-lock ordering and avoids only Set
bookkeeping/cleanup for safe ready reads. It is being remeasured.

The single-lock candidate passed 64 strict portable tests in 10 suites and the
factory, factory-capture-deinit, and trace-cacheHit reentry process cases in both
debug and optimized release modes. All six trap with the expected diagnostic;
none times out. The original and guarded double-lock versions were also checked
against the three reentry cases. Historical failing-draft evidence is retained.


## Final local integration checkpoint and method corrections

The conditional outer Self witness passed 611 focused tests / 46 suites after
updating the old declaration-index assertions. The synchronous-transient
extension then passed **613 tests / 46 suites**, strict concurrency and warnings
as errors. Actual plugin consumers cover both legacy + owned coexistence and a
separate public library/consumer boundary. New runtime oracles prove transient
per-read/diamond identity, lazy dependency short-circuiting under a value override,
all value releases, synchronous reads after close, and async reads failing closed.
MainActor and caller-isolated async-shared-to-sync-transient hard edges retain the
existing unavailable-dependency diagnostic; no unchecked resolver conversion is
introduced. An additional independent source review found no confirmed blocking regression.
It inspected the existing test logs rather than rerunning the full suites. Its
forward-transient/type-with/optional-nil coverage suggestion was added and passed
through the real plugin without a production-source change.

The final shared-cell V4 uses one original state switch and lock order, skips
only Set registration/removal for trace-disabled ready reads with no active slow
caller, and passed all six debug/release reentry traps. V3's extra state dispatch
was also rejected: ready improved but first-resolution rose 8.44→10.18 µs. V4's
observed first resolution was 8.71→8.77 µs, cold lifecycle 21.65→19.60 µs, ready
222.7→155.0 ns. These are shared-VM, three-block observations, not guarantees.
The measured runtime source and exported ordinary container AST matched that
V4 checkpoint byte-for-byte. V4 was later withdrawn after the lifetime control;
the final cell is baseline. Source-manifest and binary hashes retain both mappings.

The fixed [611-test reevaluation](macro-first-checkpoint-611.ko.md) preserves the
pre-transient score and detailed V4/competitor/prewarm-method tables. The final
report must include the added transient coverage without declaring all broader
breaking architecture work complete. Needle's official generator was attempted
without source modifications and failed in an Objective-C Foundation header on
Linux; its successful runtime-only manual bridge is not generator qualification.

A second native swift-dependencies effect fixture passes captured context,
inherited-task override and parallel override isolation. InnoDI's corresponding
explicit dependency-passing fixture passes the same observed values, with task
captures rather than implicit context propagation. This is an authoring-model
comparison, not equivalent runtime semantics or a timed speed claim.

Whole-macro phase1/2 gate correction: raw samples, old row-resampling output and
new block-resampling output are all retained. Corrected descriptive upper bounds
are 1.1565 and 1.0504; **the earlier ≤5% regression-gate pass claim is withdrawn**.
The complexity oracle and syntax-free scaling result remain valid independently.
Only after independent review freezes the final candidate should more independent
whole-macro blocks be measured. No source-level architecture benefit is counted
as proven end-to-end compile-time improvement.


## 고정 후보 15-block whole-macro 추가 측정

613-test frozen executable을 사용해 각 버전 15개 process block × 2 measured rows,
process마다 30 warmups를 실행했다. 원본 median은 290.3885ms, 후보는 304.3915ms,
ratio는 1.04822였다. 10,000 paired whole-block resamples(seed 6725)의 descriptive
interval은 0.99669–1.10811로 **사전 정의한 상한 1.05 gate를 통과하지 못했다**.
Shared VM에서 이것을 확정적 4.82% 제품 회귀라고 단정하지 않지만, 5% 이내 회귀
없음이나 전체 macro 속도 개선이 입증되었다고도 말할 수 없다.

두 test executable은 테스트가 추가되어 85,260,696B / 89,269,672B로 다르다.
같은 benchmark 함수를 filter하더라도 static test-image 구성이 잠재 confound다.
제품 source 차이만 남기고 driver/TestSupport를 같게 둔 최소 test-target 비교를
한 번 준비한다. 이것이 통과하더라도 위 full test-image 실패 결과나 실사용 회귀
우려를 지우지 않으며, 통과할 때까지 반복하는 실험이 아니다. Raw/runner hashes와
사전 protocol은 `final-macro-15-blocks`에 그대로 보존한다.


## Ready-cell V4 not adopted after lifetime control

The first-resolution roots are now explicitly retained beyond timing endpoints.
This removes ARC-lifetime uncertainty; it is not proof that earlier intervals
included teardown. The single permitted control rerun observed baseline vs V4:
cold 20.38→25.80µs, first 9.03→10.36µs, warm225.7→191.2ns. A large candidate third-
block slowdown suggests VM effects, but the first block also worsened cold/first
by about33%. Therefore V4 is NOT ADOPTED. Production OnDemandSharedCell.swift is
restored byte-for-byte from baseline; V4 is archived beside all prior drafts.
The 223→155ns earlier observation must never be attributed to the final patch.
Final correctness reruns follow the active macro-only timing window. Typed-only
prewarm measurement already used the identical original cell in both lanes.


## Matched minimal driver control and final restored-cell verification

One controlled macro run retained identical benchmark + seven TestSupport files,
source SwiftSyntax604/native backend/disabled prebuilts/Debug strict flags, and
matching33-module descriptions. Product sources were unchanged for each revision.
It observed317.231→292.777ms, ratio.92291, descriptive paired-block interval
.83379–.96623: the defined gate passes only in this control. Baseline block medians
still ranged284.7–630.7ms. This does not explain away the failed full-image run,
prove that binary size caused it, or establish a general7.7% improvement.

After reverting the ready-cell optimization, the final source passed all613
focused tests/46suites,64 portable runtime tests/10suites, real-plugin
coexistence/public-boundary/forward/type-with/nil-override checks, and all6
reentry trap processes again. The final adopted score is7.7/CS8.0/DX7.4;
the prior7.8/8.1/7.4 checkpoint is historical. Whole-product Apple qualification,
retained heap/allocation measurements, real-user migration trials and unsupported
owner forms remain explicitly unqualified.


Final micro-repair: cache the computed transient-member projection once before
owned factory generation, instead of re-filtering all members on every ordered
index. This removes a newly introduced T×N scan. Strict 613 tests and the real
plugin reran successfully; actual positive-fixture expansions before/after are
byte-identical (SHA-256 939e652641a75a3ab110699e64b892b5913152b18d3de7cf72ff86bd6e758c39).
The timed ordinary macro fixture does not enable this path, but timed executables
are still identified as the prior source checkpoint, not silently relabeled final.
No further timing run was performed.
