# GenerateMock contract qualification

Date: 2026-10-04. This is a per-claim qualification of the mock items in the
7.0 remediation report, not an acceptance of the report's aggregate score.
The retained baseline plugin's mock-source hashes matched the saved source
files. Compiler and runtime controls ran before selecting the corresponding
lowering or unsupported-shape diagnostic.

| Claim | Baseline evidence and counterexamples | Result |
| --- | --- | --- |
| P1-01c: default-isolation initializer | Unannotated and explicitly MainActor protocols both constructed and ran on MainActor with default MainActor isolation. A separate explicitly `nonisolated` protocol lost that modifier on its peer and failed outside MainActor. The original report's exact reproducer was unavailable. | Preserve explicit `nonisolated` on the mock. The tested unannotated-on-MainActor case is not a reproduced bug; no general target-setting inference is claimed. |
| P2-06a: nonescaping closures | Direct nonescaping closure parameters failed when retained, including generic-handler erasure. | Unsupported, with a reason at `@GenerateMock` and no partial peer. Optional closures, escaping closures and C function pointers remain supported. |
| P2-06b: autoclosures | Plain `@autoclosure` failed retention. `@autoclosure @escaping` already compiled and remained unevaluated until its recorded closure was invoked. | Reject the nonescaping form; preserve and document lazy escaping recording. The escaping-form failure claim is refuted by the control. |
| P2-06c: variadics | The method received an array but the call-record field used the scalar element type. | Preserve the variadic witness and record an array, including zero arguments. Generic handlers receive the complete array as one erased argument. |
| P2-06d: ownership and transfer | Typed consuming/borrowing/sending annotations were illegal stored-property types. Generic consuming inputs were consumed twice. Sending result storage/casts were invalid. Separate language controls proved Copyable parameter retention with explicit copies. | Preserve supported Copyable ownership parameters. Concurrent storage first copies to immutable locals before entering Sendable closures. Sending results and explicitly noncopyable/nonescapable generic inputs receive early unsupported diagnostics. |
| P2-06e: `generation` input | The generated metadata field and input field redeclared the same name. | Reserve metadata `generation`; allocate an available numeric suffix to the input field and keep external labels. Concurrent generation bindings cannot replace caller arguments. |
| P2-06f: protocol `Self` | Mutable/stored covariant Self was invalid, and a nested record's Self referred to the record. Generic erased-handler Self returns were already valid. | Bind Self to the final mock. If a generic parameter shadows that class name, bind through a collision-safe outer typealias. Existing generic Self-return behavior remains valid. |
| P2-06g: helper collisions | Zero-argument method/helper, private state, private return slot, error-constructor and concurrent snapshot-constructor collisions reproduced. Type/value namespace examples and same-named methods with arguments compiled successfully. | Allocate private/method helper names around real conflicts; qualify shadowed member access; use a type-directed snapshot initializer. Preserve valid type/value and labeled-method cases. Existing fixed aggregate-API collisions still diagnose. |
| P2-06h: generic handler trap | An identity handler received the generated handler closure instead of a value argument named `handler`, then trapped. A generic **type parameter** named `handler` worked. Returning the wrong erased type deliberately trapped as documented. | Generated locals cannot hide input bindings. The valid identity handler now succeeds; the wrong-return-type precondition remains part of the erased-handler contract. |

Independent review caught two candidate regressions before publication:
the generic type parameter that shadowed the final mock name, and overbroad
rejection of `@convention(c)` function pointers. Both controls pass on the
retained baseline, fail on the retained intermediate candidate, and pass after
correction. The concurrent snapshot constructor was additionally reproduced
against both the baseline and intermediate candidate before correction.

## Committed regressions

- [GenerateMock contract tests](../../Tests/InnoDIMacrosTests/GenerateMockContractTests.swift)
  cover source diagnostics, binding hygiene, Self substitution, ownership,
  variadics, supported closure forms and collision counterexamples
- [Recording consumer](../../Tests/ExternalConsumerFixtures/pass/generate-mock-recording-contracts/)
  executes ordinary and Sendable generated mocks, checks recorded values and
  reset generations, and preserves the valid generic/closure cases
- [Default-isolation consumer](../../Tests/ExternalConsumerFixtures/pass/generate-mock-default-actor/)
  checks implicit/explicit MainActor and explicit nonisolated protocols
- [Unsupported lifetime consumer](../../Tests/ExternalConsumerFixtures/fail/generate-mock-recording-lifetimes/)
  requires the specific nonescaping, transfer-result and noncopyable diagnostics
- Existing mock macro and variant snapshot suites remain in the focused run;
  the Sendable snapshot changes only the explicit type on the reset snapshot
  initializer

## Local evidence boundary

The final focused run passed 61 tests in three suites. Three official Linux
consumer compilers (Swift 6.2, 6.3 and 6.4) each completed 65 command/run
observations, including intended diagnostic failures and the intentional
erased-handler misuse trap. All 195 outcomes matched their expectations;
source and tool hashes were stable through the runs. All three used one macro
plugin built with Swift 6.4 and source-built SwiftSyntax 604. This is not a
matched-version package-build claim.

The ordinary and default-isolation consumer fixtures also execute locally.
The Linux ordinary projection removes only the call into the concurrent
fixture and replaces the import with the exact public macro declaration; it
does not replace concurrent storage with a fake implementation. The complete
concurrent fixture compiles to an object against a public-signature-only
projection of `DIConcurrentValueBox` and `DIConcurrentMockState`. That checks
generated syntax, ownership and Sendable closure captures, but supplies no
runtime method bodies and is never linked or executed.

Actual `os`/`OSAllocatedUnfairLock` storage execution and complete Apple package
integration remain the hosted external-consumer CI boundary. No TSan or mock
performance result is claimed here.

The frozen plugin has SHA-256
`bffc09c0f9c15c6c4638dcdd87c7155d9e2da59afebddaab5263c042d8a3a9de`.
Its first copied artifact lost executable mode; mode was restored from the
original to `0755` without changing these bytes. Subsequent invocation smoke
compiled and ran both the Self-shadow and C-pointer controls from that exact
frozen path. This packaging failure is distinct from product source behavior.
