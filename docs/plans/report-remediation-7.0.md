# 7.0 report remediation plan

Baseline: `064f1fc7fb8820d56181c17065be9b356845bdb5` (PR #52).
The baseline's selected CI passed; the cases below are additional boundaries.
The supplied report is an input, not a verified test record. Its original
worktrees, TSan logs and timing samples are unavailable here. The first three
P1 claims are available as summaries, not their complete original reproducers.

## Contract and sequence

Keep macro-first typed wiring and the published lifecycle guarantees. Do not
introduce reflection, a service locator, a global resolution cache, or an
unchecked Sendable escape to make a test compile. Rejected performance
experiments remain excluded. Avoid unrelated dependency or formatting changes.

1. Fix migration access-level and trivia regressions; retain original/output
   compilation and idempotence evidence, including multiple source files.
2. Qualify and fix legacy deferred concurrency, actor/default-isolation
   behavior, async consumer access and feature-root import boundaries.
3. Qualify and fix graph collection identity handling and validation snapshot
   consistency. A signature must describe the exact bytes validated.
4. Clarify caller/provider cancellation outcomes and supported public names;
   reject or correctly lower unsupported mock parameter shapes.
5. Resolve each remaining runtime, plugin, documentation and performance
   allegation separately. A negative result or missing required platform is a
   recorded outcome, never an implicit pass.
6. Review the integrated patch independently, run applicable portable and
   actual-consumer checks, then push the completed series to PR #52 and follow
   required CI for its final head. No merge, tag or release is included.

Each correction gets a focused commit with a regression that fails on the
relevant prior source. Tests must verify behavior or a precise diagnostic,
not mirror implementation. Use existing compiler/dependency caches where
possible. Coordinate CPU-intensive work with other VM tasks. Keep exact
source/toolchain/command/exit evidence for external compiler fixtures.

Apple-only behavior is qualified by hosted PR CI where its fixture runs. No
new user-Mac task is authorized. Performance claims require a separately fixed
protocol and ordinary consumer workload; external percentages and scores are
not acceptance criteria. Do not expand to prebuilt artifact distribution.

## Tracking legend

- **Reproduced**: bounded local reproduction exists; its stated scope matters.
- **Static**: a concrete source path supports the concern; add an executable
  regression before changing it when feasible.
- **Open**: claim still needs qualification or scope clarification.
- **Policy hold**: prepare a proposal only. Repository security settings,
  credentials, auto-merge policy and workflow permission behavior need separate
  approval; preserve the user's existing major-update preference.

No item is marked fixed in this initial plan. Completion records will identify
the correction/rebuttal, commit, test and remaining limits per item.

## P1 intake

| ID | Supplied claim and qualification boundary | Initial state |
| --- | --- | --- |
| P1-01a | Default MainActor isolation conflicts with ordinary `withOverrides`; generated-language mechanism reproduced, actual macro consumer pending | Reproduced |
| P1-01b | Same issue in owned construction | Static |
| P1-01c | Mock initializer under default isolation; exact original example unavailable | Open |
| P1-02 | Actor caller and non-Sendable async accessor; distinguish transient payload from shared receiver crossing | Reproduced |
| P1-03a | Legacy unchecked deferred cell bypasses payload/capture concurrency checking; original TSan evidence unavailable | Static |
| P1-03b | Eager async work can start before transient resolver binding; owned admission differs | Static |
| P1-04 | Migration creates cross-file implicit/explicit import-access conflict; stub-module compiler reproduction | Reproduced |
| P1-05 | Migration removes an already adequate explicit internal import | Reproduced |
| P1-06 | Attribute/modifier trivia combines tokens; some invalid semantic output passes parse guard | Reproduced |
| P1-07 | Conditional duplicate container IDs reach trapping multibinding dictionary construction | Static |
| P1-08 | Cache-hit source is reread after its signature was calculated | Static |
| P1-09 | `canImport` is not file import visibility; exact Apple helper consumer pending | Reproduced |
| P1-10 | Generated owner/view/prewarm types exposed with implementation-style names | Open |
| P1-11 | Cancelled preparation waiter reports cancelled while provider remains running; retry then rejects | Reproduced |
| P1-12a | Major auto-merge with no review/cooldown: enabled variable is true, but current native policy prerequisites are missing and fail closed | Policy hold |
| P1-12b | Manual performance measurement runs with repository-write credential; separate read-only measurement from writing | Policy hold |
| P1-12c | Tag-creation controls and release authority; do not blindly forbid legitimate release creation | Policy hold |

## P2 intake, split from the report's compound rows

| ID | Supplied claim and qualification boundary | Initial state |
| --- | --- | --- |
| P2-01 | Declaration-order legacy close gives dependants closed/failure outcomes; reported 99/100 frequency unverified | Static |
| P2-02 | Async on-demand task priority does not escalate for higher-priority readers; reported QoS values unverified | Open |
| P2-03a | `closeAsyncProviders` naming obscures on-demand-only scope | Static |
| P2-03b | Reentry traps omit provider name | Open |
| P2-04 | Explicit MainActor async-on-demand captures use a different isolation decision from option-enabled containers | Static |
| P2-05 | Invalid async collection emits duplicate macro/compiler diagnostics | Open |
| P2-06a | Mock nonescaping closure storage | Static |
| P2-06b | Mock autoclosure handling; distinguish escaping support | Static |
| P2-06c | Mock variadic recording uses scalar field type | Static |
| P2-06d | Mock consuming/sending parameter/return shapes; function-level consuming already rejects | Static |
| P2-06e | Mock `generation` parameter collides with generated field | Static |
| P2-06f | Mock covariant Self changes binding in nested records | Static |
| P2-06g | Mock helper-name collisions beyond existing protections | Open |
| P2-06h | Generic handler trap: distinguish documented erased-handler misuse from valid-handler failure | Open |
| P2-07 | Plugin reports become distributed target resources; actual application artifact unavailable | Open |
| P2-08a | Conditional mutually exclusive declarations get duplicate-semantic-identity diagnostic | Open |
| P2-08b | Identity diagnostics omit source location | Open |
| P2-09a | Build plugin does not forward documented environment controls | Open |
| P2-09b | Killed coordinator leaves an unexplained approximately 30-second wait | Open |
| P2-10a | Cached failure positions become stale after trivia edits | Static |
| P2-10b | Symlink source directories fail validation | Open |
| P2-10c | FAST_BUILD documentation example does not compile | Open |
| P2-11a | No-op/21-target edit overhead; reported timing data unavailable | Open |
| P2-11b | Debug coordinator and repeated target-scope parsing costs | Open |
| P2-11c | Proposed prebuilt artifact distribution | Out of scope |
| P2-12a | Owned generated-code/compiled-artifact growth; reported ratios unavailable | Open |
| P2-12b | Owned build-cost benchmark coverage | Open |
| P2-13a | Public import incorrectly treated as namespace re-export | Reproduced |
| P2-13b | Ambiguous migration diagnostic omits module names | Open |
| P2-13c | Comment duplication/loss and indentation damage | Reproduced |
| P2-13d | Recovery basename exceeds NAME_MAX for long source names; Darwin write not executed | Static |
| P2-14a | README actor `withOverrides` example | Open |
| P2-14b | Macro dump helper emits no output on default Swift 6.4 build | Open |
| P2-14c | Korean DIContainer reference retains nonexistent root parameter | Open |
| P2-14d | Overview retains obsolete 4.x descriptions | Open |
| P2-15 | Executable snippet coverage omits important OwnedContainers/README journeys | Open |
| P2-16a | Fork events can invalidate unrelated Dependabot proof/automation | Open |
| P2-16b | CODEOWNERS not enforced by current ruleset | Policy hold |
| P2-16c | PR-edited CI can self-attest; evaluate actual trusted-main policy boundary | Policy hold |

## Release-policy observation

Read-only settings on 2026-10-04 show `RELEASE_MAIN_RULESET_ID=15303479`
contains an OrganizationAdmin bypass. This conflicts with the existing release
workflow's no-bypass preflight. It is separate from passing PR CI, and requires
an explicit settings decision rather than a product-code workaround. The tag
ruleset prevents updates/deletion and intentionally permits initial creation.

## Evidence already available

- Exact migration-source rewrite with 16 parser fixtures; before/after
  multi-file compilation using stub modules, not Apple framework/CLI writes.
- Three bounded Swift 6.4 language mechanisms for default actor isolation,
  async property crossing and module availability versus import visibility.
- Exact DIAsyncScope/DIAsyncOwner source reproduction: preparation reports
  cancelled, actual provider remains running, retry rejects, original work
  completes normally. This confirms an outcome-reporting gap, not failed
  cancellation isolation or failed cleanup.
- Read-only source and current GitHub settings inspection. No attack execution,
  configuration change or supplied benchmark claim is treated as a result.

## Workspace recovery

At 2026-10-04 07:48 UTC the active VM filesystem stopped exposing the current
DI workspace. The unpushed plan commit had returned short ID `2287132`.
This plan is reconstructed from its retained patch text on the exact remote
baseline in a separate recovery checkout. Earlier results above are historical
observations, not verification of this restored checkout. Relevant regressions
will be rerun after restoring the toolchain and reviewed patch. The original
workspace was not overwritten or cleaned.

## Stage 1: import access and trivia

P1-04/05/06 and P2-13c are addressed by the first migration correction. A
source-only migrator cannot infer whether SwiftUI types occur in public API:
keeping internal can narrow the removed re-export, while unconditional public
promotion can produce `UnusedImportAccess` under warnings-as-errors. Ambiguous
cases therefore retain the source and block writes with a targeted diagnostic;
`--swiftui-import-access internal|package|public` records the operator's explicit choice
for that root. Exported imports always use explicit public access. This is an
intentional refinement of the original automatic-visibility plan, supported by
old/new module and downstream-client compiler controls.

The initial source reproduced 14 assertion/compiler issues. Its first proposed
fix was rejected by independent review for public API narrowing and invalid
`@_exported internal` output; those observations are preserved. The revised
portable suite runs the exact transformation and existing trivia/conditional
tests, plus before/after public API and strict internal-only consumer builds
under both import-default modes. Native Darwin `--write`/rollback qualification
remains covered by committed tests for the subsequent Apple CI run. Do not
interpret the portable subset as a full migration package pass.

## Stage 2: legacy deferred isolation

P1-03a/03b are confirmed by actual-plugin consumers: the baseline accepts
three unsafe capture cases, and a separate executable reaches the premature
deferred-resolution trap while initialization is still in progress. The
candidate removes the legacy unchecked conformance and completes resolver
bindings before creating async work. The three captures receive their intended
full-compilation diagnostics; the formerly trapping consumer returns 42.
Checked exclusive transfer, synchronous non-Sendable values and actor-local
access remain supported. No TSan result or runtime performance gain is claimed.

The related P2-04 initializer inconsistency is corrected for explicit versus
option-enabled MainActor containers. Macro and portable-consumer evidence pass;
the added native async-on-demand runtime test still requires Apple CI.

Portable validation: 112 core and 534 executed macro tests passed, with four
opt-in benchmark/export skips (Swift Testing reports 538 macro registrations).
Only the Darwin-dependent `uniqueBindingRepairBuildsAndGraphs` integration
method is excluded; its five neighboring mechanical-fix tests remain in a
hash-recorded portable projection. The complete portable plugin validator also
passes existing owned/prepared/public/lifetime cases and new legacy fixtures.
This does not close P1-01 default-isolation or P1-02 async-accessor work.


## Stage 3: caller isolation and default-actor boundary

P1-02 is addressed by documenting and testing an **existing** supported
property modifier, `nonisolated(nonsending)`. The report's accessor-only syntax
limitation does not imply that the property declaration cannot carry it.
The unannotated read still fails as expected. A new `resolveX()` public-method
prototype was investigated, preserved separately, and removed from the product
diff because it would add unnecessary names and generated API surface.

Actual public consumer compilation and execution cover a non-Sendable transient
result, an async dependency chain, a shared Sendable result on a non-Sendable
receiver, callable payloads, overrides, errors, trace events, MainActor and an
independent actor caller. Existing owned access and close also pass. Hidden
members and off-MainActor non-Sendable results remain rejected. Shared async
payloads still require Sendable; the modifier does not relax factory captures.

Official Linux Swift 6.2, 6.3 and 6.4 consumers passed 51 matrix commands/runs
plus 15 additional mixed async/owned and negative controls. The macro executable
was built with Swift 6.4 and source-built SwiftSyntax 604 for all three consumer
versions. This is consumer-language/runtime evidence, not a matched-version
package build or Apple result. Two new real-package compile-pass fixtures are
picked up by the existing hosted ExternalConsumerContractTests on publication.

P1-01a/b remain a verified compiler/macro-context limitation. Unannotated
containers under `-default-isolation MainActor` fail in all three compilers;
explicit `@MainActor`, the role's `mainActor: true`, and `nonisolated struct`
construction pass, including owned preparation. The documentation states this
supported workaround and does not claim automatic default-isolation inference
was fixed. P1-01c mock-specific behavior remains in the mock qualification stage.
P2-14c's obsolete Korean `root` argument is corrected to the existing role API.

The declaration-based approach received an independent read-only source review.
The complete portable plugin suite is rerun with these committed consumer sources;
Apple async-on-demand and matched-toolchain package qualification remain CI gates.


## Stage 4: explicit feature hosting and complete actor forwarding

P1-09 was reproduced with the same actual macro consumer: it compiled when
SwiftUI modules were absent, then failed merely when those modules became
searchable, although its source imports had not changed. The import-only
qualification uses explicitly synthetic SwiftUI interfaces and does not claim
SwiftUI rendering or host lifecycle proof.

Plain feature roots now emit only their existing zero-argument helper.
`FeatureRoot(..., hosted: true)` explicitly requests the identity/close overload;
its source file imports SwiftUI and InnoDISwiftUI. `hosted:` requires a literal
Bool. The old public initializer remains unchanged. Compiler-emitted API
inspection on Linux 6.2/6.3/6.4 found exactly the same two intended additions,
`FeatureRoot.hosted` and `init(_:as:hosted:)`, while preserving its four existing
symbols. The narrow baseline proposal awaits independent review before replacing
the checked-in contract. Full Apple product API verification remains required.

The broader consumer exposed an unpublished intermediate regression: the same
explicit-MainActor parent/child-override fixture passed remote 064f1fc, failed
local 5b2c04e, and passes the corrected generator. The initializer's effective
actor policy is now also used by override storage/callbacks, lifecycle close,
and component protocols/mount witnesses. This is separate from the unsupported
implicit target-default inference described in stage 3.

Validation: 537 executed macro tests pass, with four opt-in skips (541 reported
registrations); the same Darwin integration exclusion remains. The complete
portable actual-plugin suite passes. Fifteen additional compiler/build/run
operations verify explicit actor overrides, child overrides, component mounting,
and mixed owned preparation on Swift 6.2/6.3/6.4 consumers with the shared
6.4-built plugin. Actual SwiftUI lifecycle tests are updated to opt in, and a new
hosted external-consumer fixture proves file-level imports in supported Apple CI
when published. No rendering/Apple result is claimed from the VM.


## Stage 5: declaration-local collection analysis

P1-07 is reproduced and corrected. An exact production collector subset crashed
with `Dictionary` duplicate-key SIGILL while walking two `#if`/`#else` container
declarations with the same semantic identity and ordered collection metadata.
The regression uses an ordered collection, which permits the shared/transient
contributor lifetime contrast; the earlier provider-collection diagnostic input
is retained separately and is not described as a valid construction graph.

Collection metadata is now resolved against providers in the current declaration,
then appended to the complete result. Both declarations remain present for later
identity validation. Invalid repeated members and collection declarations never
trap and never choose an arbitrary metadata winner. Three direct collector tests
pass against exact production source on Linux; the baseline ordered case still
traps as expected in its preserved source snapshot.

This closes the collector crash, not P2-08a's separate final-graph conditional
identity policy. The collector neither chooses a compiler configuration nor
silently merges mutually exclusive declarations. Full graph/workspace validation
and conditional-identity diagnostics remain separately tracked.
