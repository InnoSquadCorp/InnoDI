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

The existing example jobs use exact consumer impact to skip unaffected SampleApp, SwiftUIExample or PreviewInjection only after validating a receipt. Full-mode commands retain the original build/test and SampleApp run. The current root has no tracked Package.resolved, so admission presently stays full. A real reproducibility/lock contract must be prepared with Swift before narrowing; no synthetic lock was invented.

Full `swift test` remains explicit: `--filter` alone does not prove a narrower test compilation graph. Separate test packages or independently validated native bundle execution are needed before promising product-only test compilation. Existing full coverage and release gates are retained.

Examples to inspect:
- SwiftUI: mode=scoped-build-plan; affected products=InnoDISwiftUI; affected tests=InnoDISwiftUITests; test-build products=InnoDI, InnoDISwiftUI
- migration: mode=scoped-build-plan; affected products=InnoDI-Doctor, InnoDI-Migrate; affected tests=InnoDIDoctorCoreTests, InnoDIMigrationCoreTests; test-build products=InnoDI-Migrate
- shared core: mode=full; affected products=InnoDI, InnoDI-DependencyGraph, InnoDI-Doctor, InnoDI-Migrate, InnoDIDAGValidationPlugin, InnoDISwiftUI, InnoDITesting; affected tests=InnoDIBuildSupportTests, InnoDICoreTests, InnoDIDependencyGraphCLITests, InnoDIDoctorCoreTests, InnoDIMacrosTests, InnoDIMigrationCoreTests, InnoDIRuntimeTests, InnoDISwiftUITests, InnoDITestingTests; test-build products=InnoDI, InnoDI-DependencyGraph, InnoDI-Migrate, InnoDISwiftUI, InnoDITesting

## Before any remote rollout

1. Rebase these local changes onto the intended final repository SHA and rerun all policy tests.
2. Run Apple SwiftPM dump verification, actual target builds, complete test discovery and full release gates. The publication VM has no Swift/Xcode. Earlier isolated Mac validation built all three example consumers and passed their 10 tests plus SampleApp execution, but full runtime validation did not pass. The workflow recipe contract repair was reconstructed for this PR from the Mac finding; its Python recipe is verified here, while this exact Swift wrapper still needs hosted compilation.
3. Validate real GitHub native parallel execution, failure/cancellation propagation and REST job-step names with an explicitly authorized non-release run. Do not infer these from a linter pass.
4. Review required-check and proof migration together. No repository settings are changed by this preparation. Read-only authenticated API inspection on 2026-10-07 confirmed no repository-level override for the three new feature variables.
5. Measure runner queue time separately from actual execution; no speed or cost reduction is claimed.

The existing Ruby 3.3.8 runtime under flow-review-tools/bin can run Ruby-dependent policy tests when added to PATH. Compiler-free tests and YAML checks do not substitute for Apple or hosted validation.

## Real resolution bootstrap

Existing Apple example jobs collect root and example locks with real `xcrun swift package resolve` while a required lock is absent. No new runner job or permission is added. Artifacts include the immutable candidate, run/attempt, Xcode/Swift version, exact committed manifest bytes, live dump-package digest, and unchanged generated lock bytes. Resolver failures remain failures and retain their diagnostic output. Each manifest is checked against the candidate commit and all manifests/locks are rechecked after the final resolution. Once root and that consumer's lock are tracked, the bootstrap is skipped.

These artifacts are resolution evidence only. They must be verified against the exact trusted run and candidate before copying the generated lock files into the PR; no pins or originHash are handwritten. Cross-toolchain dumps/pins and the actual scoped tests still require validation. Native Apple test-package qualification is a separate step and does not grant success from lock generation alone.

## Qualified leaf test execution

`ci_product_test_scope.py` can admit exactly one source-only InnoDISwiftUI or InnoDITesting change after committed real-toolchain qualification exists. CI Plan and CI Required independently recompute the exact Git/qualification proof. The existing fast-tests job then executes the standalone test consumer with a fresh scratch directory and verifies native build descriptions plus actual compiled first-party modules. A test filter is not used as a compilation boundary. The selected API gate uses the unchanged semantic normalizer and is admitted only after equivalence with the full compiler contract and baseline has been proven on the same toolchain.

Testing-only changes can omit example and documentation jobs because those consumers depend on InnoDI/SwiftUI. SwiftUI changes select both relevant SwiftUI examples (with exact matching tracked root/example dependency pins and force-resolved execution) while retaining documentation checks. All unknown/shared/mixed/test/manifest/toolchain or unqualified inputs keep the original jobs; bot, main, merge queue, release, coverage and compatibility contracts remain full. A changed or missing runtime proof fails the selected job and cannot bless skipped gates.

Global DAG/alias validators and policy/compiler self-tests remain explicit shared checks. These may build validator tools or small probe modules; this is not a claim that every compiler invocation belongs solely to the edited shipping product. Other product test packages, especially CLI/Migrate/Doctor with internal modules and path-sensitive fixtures, remain full until separately proven.

Qualification bootstrap runs in existing Xcode 26.6 jobs only after the original full test build (fast or coverage) and full API validation succeed. It captures full/scoped discovery, actually executes strict scoped tests in fresh scratch directories, verifies first-party compile closure and selected/full API equivalence, and uploads raw evidence. No qualification file is synthesized in this VM. Until generated locks and successful qualification artifacts are verified and committed, the original full fast-test path remains active. Changes to a qualification or its bound manifests/locks/helpers/baseline/test inputs force real bootstrap even when a qualification file already exists. A self-declared replacement record cannot skip this verification; stale proof never authorizes narrowing.

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
