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
