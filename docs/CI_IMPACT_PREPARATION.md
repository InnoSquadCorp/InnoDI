# Local CI impact preparation

Status: proposed CI change for review. Product selection and job cancellation are enabled by default for eligible PRs. Explicit disable overrides remain available; protection and release settings are unchanged.

## Implemented PR path

An ordinary PR containing only modified, regular allowlisted Markdown or `.github/FUNDING.yml` files may use compiler-free static policy checks. Exact merge-base/head Git blob IDs and code signatures are recorded. CI Required re-reads the immutable event anchors, recomputes the complete changed-file inventory and blob proof, and rejects missing, failed, cancelled or unexpectedly skipped results. The required check has no workflow-level path filter.

All code fences and indented code are protected. Unproven blobs, executable changes, opaque HTML/DocC directives, release metadata, unknown or mixed changes, deleted/renamed/mode-changed files are conservative. Missing diff evidence selects full validation. The release-validation label remains full. Main, merge queue, manual and release gates retain their previous full semantics, including exact-tree proof rules.

Native `parallel` is limited to reviewed independent read-only policy checks. No SwiftPM build, shared `.build`, DerivedData, Package.resolved mutation, sanitizer or performance workload is overlapped. Native groups have an implicit join: every child must finish successfully. No error-tolerance or conditional native children are introduced.

## Linter compatibility

`native_parallel.py` accepts a deliberately small schema: 2–10 named run-only children, optional shell/timeout, no nested native controls, IDs, environment publishing, output dependencies, conditional or continue-on-error children. It produces a same-line-count serial projection only for actionlint 1.7.12. GitHub executes the original YAML. All ordinary actionlint diagnostics remain enforced; only the existing exact-position concurrency.queue exception remains. Negative tests reject malformed schemas. Real hosted parallel-child REST step inventory must be verified before rollout; the bot and main-reuse evidence checks remain fail-closed.

## Executable default-on product selection

The reviewed inventory contains 27 package targets, 7 products and 89 checked-in consumer fixture/package entries. It is bound to the exact Package.swift SHA-256. Local target dependencies include a conservative union of conditional edges. External package dependencies and full manifest semantics are unchanged.

`Tools/ci-product-impact.py` computes changed targets, reverse-dependent products/tests/consumers, and a separate test compilation dependency closure. Unknown paths, generated files, resources, manifest/toolchain/plugin/shared-support changes and mixed evidence retain full fallback. Use `--verify-dump` against an actual Apple SwiftPM dump before using the map operationally.

`Tools/ci-product-impact.py` is the planner; the separate `Tools/ci_product_execution.py` adapter is now wired into existing workflows. An unset/empty `INNODI_PRODUCT_CI` or `true` enables admission; `false` or an unrecognized value disables it. Workflow values are normalized before Python execution. Admission rechecks the exact checkout/event/merge parents, complete Git diff, clean tracked and relevant untracked inputs, committed dependency lock, graph/manifest identity and real SwiftPM dump. Missing evidence executes the original full recipe. No manifest is rewritten. Exact command/result receipts are recomputed before acceptance; missing, forged, stale or failed receipts cannot grant success.

The existing example jobs use exact consumer impact to skip unaffected SampleApp, SwiftUIExample or PreviewInjection only after validating a receipt. Full-mode commands retain the original build/test and SampleApp run. The root and all three examples now have tracked Package.resolved files from verified hosted SwiftPM resolution. Missing or mismatched remaining admission evidence still selects the original full recipe; no synthetic lock was invented.

Full `swift test` remains explicit outside the qualified SwiftUI/Testing consumers described below: `--filter` alone does not prove a narrower test compilation graph. Those two separate test packages now have hosted compilation, discovery, and API evidence. Existing full coverage and release gates are retained.

Examples to inspect:
- SwiftUI: mode=scoped-build-plan; affected products=InnoDISwiftUI; affected tests=InnoDISwiftUITests; test-build products=InnoDI, InnoDISwiftUI
- migration: mode=scoped-build-plan; affected products=InnoDI-Doctor, InnoDI-Migrate; affected tests=InnoDIDoctorCoreTests, InnoDIMigrationCoreTests; test-build products=InnoDI-Migrate
- shared core: mode=full; affected products=InnoDI, InnoDI-DependencyGraph, InnoDI-Doctor, InnoDI-Migrate, InnoDIDAGValidationPlugin, InnoDISwiftUI, InnoDITesting; affected tests=InnoDIBuildSupportTests, InnoDICoreTests, InnoDIDependencyGraphCLITests, InnoDIDoctorCoreTests, InnoDIMacrosTests, InnoDIMigrationCoreTests, InnoDIRuntimeTests, InnoDISwiftUITests, InnoDITestingTests; test-build products=InnoDI, InnoDI-DependencyGraph, InnoDI-Migrate, InnoDISwiftUI, InnoDITesting

## Publication validation and operational limits

1. The published changes are based on main `821e9ac3c26f2a8899cfcc972c349c00a5e058ed`. Revalidate against the intended final SHA before merging.
2. The publication VM has no Swift/Xcode. Hosted run 37739258042 at `ba6f1b2de4f330ba1e0165e346914df32d3460a3` subsequently passed full coverage/API, sanitizer, consumer, platform and toolchain gates, including the reconstructed workflow recipe contract. The initial isolated Mac limitations do not substitute for or invalidate this later exact-head evidence.
3. Native parallel static validators and their REST child-step names passed in hosted policy jobs. Keep exact failure/cancellation contracts; a linter pass alone is insufficient evidence.
4. Review required-check and proof migration together. No repository settings are changed by this preparation. Read-only authenticated API inspection on 2026-10-07 confirmed no repository-level override for the three new feature variables.
5. Measure runner queue time separately from actual execution; no speed or cost reduction is claimed.

Compiler-free policy tests use Python and Ruby 3.3.8. These tests and YAML checks do not substitute for Apple or hosted validation.

## Real resolution bootstrap

Existing Apple example jobs collect root and example locks with real `xcrun swift package resolve` while a required lock is absent. No new runner job or permission is added. Artifacts include the immutable candidate, run/attempt, Xcode/Swift version, exact committed manifest bytes, live dump-package digest, and unchanged generated lock bytes. Resolver failures remain failures and retain their diagnostic output. Each manifest is checked against the candidate commit and all manifests/locks are rechecked after the final resolution. Once root and that consumer's lock are tracked, the bootstrap is skipped.

These artifacts are resolution evidence only. They must be verified against the exact trusted run and candidate before copying the generated lock files into the PR; no pins or originHash are handwritten. Cross-toolchain dumps/pins and the actual scoped tests still require validation. Native Apple test-package qualification is a separate step and does not grant success from lock generation alone.

## Qualified leaf test execution

`ci_product_test_scope.py` can admit exactly one source-only InnoDISwiftUI or InnoDITesting change after committed real-toolchain qualification exists. CI Plan and CI Required independently recompute the exact Git/qualification proof. The existing fast-tests job then executes the standalone test consumer with a fresh scratch directory and verifies native build descriptions plus actual compiled first-party modules. A test filter is not used as a compilation boundary. The selected API gate uses the unchanged semantic normalizer and is admitted only after equivalence with the full compiler contract and baseline has been proven on the same toolchain.

Testing-only changes can omit example and documentation jobs because those consumers depend on InnoDI/SwiftUI. SwiftUI changes select both relevant SwiftUI examples (with exact matching tracked root/example dependency pins and force-resolved execution) while retaining documentation checks. All unknown/shared/mixed/test/manifest/toolchain or unqualified inputs keep the original jobs; bot, main, merge queue, release, coverage and compatibility contracts remain full. A changed or missing runtime proof fails the selected job and cannot bless skipped gates.

Global DAG/alias validators and policy/compiler self-tests remain explicit shared checks. These may build validator tools or small probe modules; this is not a claim that every compiler invocation belongs solely to the edited shipping product. Other product test packages, especially CLI/Migrate/Doctor with internal modules and path-sensitive fixtures, remain full until separately proven.

Qualification bootstrap runs in existing Xcode 26.6 jobs only after the original full test build (fast or coverage) and full API validation succeed. It captures full/scoped discovery, actually executes strict scoped tests in fresh scratch directories, verifies first-party compile closure and selected/full API equivalence, and uploads raw evidence. No qualification file is synthesized in this VM. The generated locks and successful qualification records are now verified and committed. Missing or stale qualification still retains the original full fast-test path. Changes to a qualification or its bound manifests/locks/helpers/baseline/test inputs force real bootstrap even when a qualification file already exists. A self-declared replacement record cannot skip this verification; stale proof never authorizes narrowing.

## Hosted resolution evidence

Root and the three example locks were generated by Xcode 26.6 / Swift 6.3.3
in successful jobs of [run 37715942212](https://github.com/InnoSquadCorp/InnoDI/actions/runs/37715942212),
at PR head `57a0cf8a951b60777722143bdf7fbf9671371107` and merge candidate
`82787a5c6fc8bea830bb6eb8f4b50f9335a6bb15`. Original generated bytes are retained.
Artifacts 11526070658, 11526324404, and 11526786484 passed ZIP SHA256,
run/attempt/repository, merge-parent, committed-manifest, dump, and lock-hash
checks. All three independently generated root locks are byte-identical;
all four locks use identical dependency pins. This proves resolution and the
existing example jobs only. Independent test-consumer locks and compilation,
discovery, and API qualification remain required before narrowing root tests.

Discovery uses `swift test list --skip-build` with shared build options;
`--no-parallel` applies only to actual test execution. SwiftPM 6.3's
[List command](https://github.com/swiftlang/swift-package-manager/blob/swift-6.3-RELEASE/Sources/Commands/SwiftTestCommand.swift#L691)
does not accept the test runner's parallelism option.

Test-consumer locks were subsequently generated in the successful resolution
phase of [run 37729988043](https://github.com/InnoSquadCorp/InnoDI/actions/runs/37729988043)
(head `d1d9c8f26bbfd38bbcbab592357315cea6e32dcf`). Artifact 11531391317
SHA256 `be6bb5c624f01b0e9c0bab3bf46a872579f4441c307d66cd591b2aab74d4e4df`
passed the same provenance/hash checks, and both pins match the tracked root.
The later qualification step failed; these locks are resolution evidence only.
SwiftUI's 36 tests did run successfully in that isolated package, but no final
qualification is accepted until compile inventory, discovery and API checks pass.

Native SwiftPM descriptions contain available commands for unused dependency
products too. The checker requires every selected module to have a command,
and requires the actual fresh `.swiftmodule` outputs to match exactly the
selected dependency/test closure. An unused command cannot certify a build;
an unrelated compiled module still fails. SwiftPM may also compile a declared
build-tool plugin while loading the dependency graph, even when that plugin
is not applied by the test consumer. This setup overhead is not a claim of
zero compiler work outside selected library/test modules.

## Successful isolated-test qualification

[Run 37735555205](https://github.com/InnoSquadCorp/InnoDI/actions/runs/37735555205)
qualified both consumers at head `a7945623264c35b508aa90bbc1d2200039784146`
after successful clean full coverage and full API validation. Artifact 11532198526
SHA256 `42418b3104646d3599ac38930af5f36b5f604aac25b79228702518155a18a39b`
contains the original checked-in qualification records and raw proof. Its native
run/attempt, merge parents, bound input hashes, raw descriptions, module inventory,
and symbol graphs were checked before import.

- SwiftUI: 36 discovered tests, all matching the original full-package inventory
- Testing: 20 discovered tests, all matching the original full-package inventory
- Each fresh build compiled exactly its selected library and test module plus
  `InnoDI`, `InnoDIMacros`, and `InnoDICore`; the other shipping library was absent
- Both strict test executions and selected/full/baseline API comparisons passed

Qualification is bound to Xcode 26.6 build 17F113, Swift 6.3.3,
macOS 26.6.2, macOS SDK 26.5 build 25F70, and arm64. Changes to these live inputs
fail the selected gate until requalified. These records enable ordinary eligible
single-leaf source PR planning; shared/unknown/main/queue/release paths remain full.
The commit importing the records itself requires a fresh qualification replay.
