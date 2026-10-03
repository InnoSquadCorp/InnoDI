import Foundation
import Testing

@Suite("CI workflow hardening contracts")
struct CIWorkflowHardeningTests {
    @Test("Main reuses bounded PR proof without importing publication artifacts")
    func mainReuseKeepsFreshPublicationAndFinalProof() throws {
        let workflow = try String(
            contentsOf: packageRootURL().appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        #expect(workflow.contains("reuse-proof: ${{ steps.reuse.outputs.proof }}"))
        #expect(workflow.contains("Tools/main-ci-reuse-policy.py --event \"$GITHUB_EVENT_PATH\""))
        #expect(workflow.contains("CI_REUSE: ${{ needs.ci-plan.outputs.reuse-proof }}"))
        #expect(workflow.contains("github.event_name == 'pull_request' && '--report-only' || '--enforce'"))
        #expect(workflow.contains("revision: ${{ github.event.pull_request.head.sha || github.sha }}"))
        let appendStart = try #require(workflow.range(of: "  append-perf-history:\n"))
        let append = workflow[appendStart.lowerBound...]
        #expect(append.contains("      - ci-required\n"))
        #expect(append.contains("      - macro-tests\n"))
        #expect(!append.contains("      - sanitizers\n"))
        #expect(!append.contains("run-id:"))
        let release = try String(
            contentsOf: packageRootURL().appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        #expect(!release.contains("main-ci-reuse"))
    }

    @Test("Repository workflows use pinned actions and scoped credentials")
    func repositoryWorkflowsPass() throws {
        let result = try runCIActionPinCheck(arguments: [])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("pinned external action use(s)"))
    }

    @Test("Macro validation supersedes code changes and preserves metadata queues")
    func macroValidationCancelsSupersededRuns() throws {
        let root = packageRootURL()
        let workflow = try String(
            contentsOf: root
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let jobsStart = try #require(workflow.range(of: "\njobs:\n"))
        let workflowPolicy = workflow[..<jobsStart.lowerBound]

        #expect(workflowPolicy.contains("group: macro-tests-${{ github.ref }}"))
        // Evaluate the actual admission, queue and cancellation expressions
        // for metadata, code, base, label and manual-dispatch events.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-B", "-m", "unittest", "discover",
            "-s", "Tools/tests", "-p", "test_ci_event_routing.py",
        ]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("PR and exhaustive validation have explicit latency budgets")
    func validationLanesStaySeparated() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let fastStart = try #require(workflow.range(of: "  fast-tests:\n"))
        let exhaustiveStart = try #require(workflow.range(of: "  macro-tests:\n"))
        let consumerStart = try #require(
            workflow.range(of: "  consumer-contracts:\n")
        )
        let sanitizerStart = try #require(
            workflow.range(of: "  sanitizers:\n")
        )
        let fastJob = workflow[fastStart.lowerBound..<exhaustiveStart.lowerBound]
        let exhaustiveJob = workflow[
            exhaustiveStart.lowerBound..<consumerStart.lowerBound
        ]
        let consumerJob = workflow[
            consumerStart.lowerBound..<sanitizerStart.lowerBound
        ]

        #expect(fastJob.contains("name: Fast PR contracts"))
        #expect(fastJob.contains("if: needs.ci-plan.outputs.fast-tests == 'true'"))
        #expect(fastJob.contains("timeout-minutes: 30"))
        #expect(fastJob.contains("--no-parallel"))
        #expect(
            fastJob.contains(
                "--skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)'"
            )
        )
        #expect(
            fastJob.contains(
                "--skip 'InnoDIMigrationCoreTests.InnoDIMigrationCoreTests/publicExecutableRunsFromFreshConsumer'"
            )
        )
        // The fix-it consumer build is a clean-build contract like the
        // suites above; the exhaustive coverage gate still runs it unskipped.
        #expect(
            fastJob.contains(
                "--skip 'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'"
            )
        )
        #expect(fastJob.contains("Tools/check-public-api.py"))
        #expect(fastJob.contains("--validate-dag"))
        #expect(!fastJob.contains("--enable-code-coverage"))
        #expect(!fastJob.contains("Tools/measure-macro-performance.sh"))

        #expect(exhaustiveJob.contains("name: Exhaustive release contracts"))
        #expect(exhaustiveJob.contains("if: needs.ci-plan.outputs.macro-tests == 'true'"))
        #expect(exhaustiveJob.contains("Tools/run-coverage-gate.sh"))
        #expect(exhaustiveJob.contains("Tools/measure-macro-performance.sh"))
        #expect(!exhaustiveJob.contains("--skip 'InnoDIBuildSupportTests."))
        #expect(!exhaustiveJob.contains("external-consumer-contracts"))

        // The subprocess build contracts run beside the coverage gate.
        #expect(consumerJob.contains("name: Exhaustive consumer contracts (Xcode 26.6)"))
        #expect(consumerJob.contains("needs: ci-plan"))
        #expect(consumerJob.contains("if: needs.ci-plan.outputs.consumer-contracts == 'true'"))
        #expect(consumerJob.contains("timeout-minutes: 90"))
        #expect(consumerJob.contains("--filter StrictConcurrencyBuildTests"))
        #expect(consumerJob.contains("--filter ExternalConsumerContractTests"))
        #expect(consumerJob.contains("path: ${{ steps.cache-inputs.outputs.consumer-paths }}"))
        #expect(!consumerJob.contains("--enable-code-coverage"))
    }

    @Test("Fast PR and exhaustive jobs preserve distinct diagnostic artifacts")
    func validationArtifactsDoNotCollide() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let fastStart = try #require(workflow.range(of: "  fast-tests:\n"))
        let exhaustiveStart = try #require(workflow.range(of: "  macro-tests:\n"))
        let consumerStart = try #require(workflow.range(of: "  consumer-contracts:\n"))
        let fastJob = workflow[fastStart.lowerBound..<exhaustiveStart.lowerBound]
        let exhaustiveJob = workflow[exhaustiveStart.lowerBound..<consumerStart.lowerBound]

        // Lane-specific artifacts remain distinct even though the planner now
        // selects only exhaustive when it contains the complete fast contract.
        for report in ["escape-hatch-report", "deferred-aliases-report"] {
            #expect(fastJob.contains("          name: \(report)-fast-pr\n"))
            #expect(!fastJob.contains("          name: \(report)\n"))
            #expect(exhaustiveJob.contains("          name: \(report)\n"))
        }
        #expect(!fastJob.contains("overwrite: true"))
        #expect(!exhaustiveJob.contains("overwrite: true"))
    }

    @Test("Exhaustive CI runs isolated thread and address sanitizer suites")
    func mainCIRunsSanitizers() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let jobStart = try #require(
            workflow.range(of: "  sanitizers:\n")
        )
        let nextJobStart = try #require(
            workflow.range(
                of: "\n  swift-62-compatibility:\n",
                range: jobStart.upperBound..<workflow.endIndex
            )
        )
        let job = workflow[jobStart.lowerBound..<nextJobStart.lowerBound]

        #expect(job.contains("name: Thread and address sanitizers (Xcode 26.6)"))
        #expect(job.contains("if: needs.ci-plan.outputs.sanitizers == 'true'"))
        #expect(job.contains("timeout-minutes: 120"))
        #expect(job.contains("version: \"26.6\""))
        #expect(job.contains("--scratch-path .build/main-tsan"))
        #expect(job.contains("--sanitize=thread"))
        #expect(job.contains("--scratch-path .build/main-asan"))
        #expect(job.contains("--sanitize=address"))
        #expect(job.components(separatedBy: "--no-parallel").count - 1 == 2)
        #expect(
            job.components(
                separatedBy: "--skip 'InnoDIBuildSupportTests.(ExternalConsumerContractTests|StrictConcurrencyBuildTests)'"
            ).count - 1 == 2
        )
        #expect(
            job.components(
                separatedBy: "--skip 'InnoDIMigrationCoreTests.InnoDIMigrationCoreTests/publicExecutableRunsFromFreshConsumer'"
            ).count - 1 == 2
        )
        #expect(
            job.components(
                separatedBy: "--skip 'InnoDIMacrosTests.MechanicalFixItTests/uniqueBindingRepairBuildsAndGraphs'"
            ).count - 1 == 2
        )
        #expect(
            job.components(
                separatedBy: "-Xswiftc -strict-concurrency=complete"
            ).count - 1 == 2
        )
        #expect(
            job.components(
                separatedBy: "-Xswiftc -warnings-as-errors"
            ).count - 1 == 2
        )
    }

    @Test("Manual dispatch runs every read-only release lane without publishing history")
    func manualReleaseCandidateValidationIsReadOnly() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let jobsStart = try #require(workflow.range(of: "\njobs:\n"))
        let workflowPolicy = workflow[..<jobsStart.lowerBound]
        let appendStart = try #require(
            workflow.range(of: "  append-perf-history:\n")
        )
        let appendJob = workflow[appendStart.lowerBound...]

        #expect(workflowPolicy.contains("  workflow_dispatch:\n"))
        #expect(
            workflowPolicy.contains(
                "types: [opened, synchronize, reopened, labeled, unlabeled, edited]"
            )
        )
        for job in ["macro-tests", "consumer-contracts", "sanitizers",
                    "swift-62-compatibility", "xcode-27-compatibility",
                    "apple-platform-builds", "path-identity"] {
            #expect(workflow.contains("if: needs.ci-plan.outputs.\(job) == 'true'"))
        }
        #expect(!workflowPolicy.contains("ready_for_review"))
        let coordinator = try String(
            contentsOf: packageRootURL().appendingPathComponent(".github/workflows/dependabot-auto-merge.yml"),
            encoding: .utf8
        )
        #expect(coordinator.contains("ready_for_review"))
        let requiredStart = try #require(workflow.range(of: "  ci-required:\n"))
        let requiredJob = workflow[requiredStart.lowerBound..<appendStart.lowerBound]
        #expect(requiredJob.contains("    name: CI Required\n"))
        #expect(requiredJob.contains("    if: ${{ always() }}\n"))
        #expect(requiredJob.contains("- name: Verify prior validation for metadata\n"))
        #expect(requiredJob.contains("Tools/verify-ci-metadata.py --check 'CI Required'"))
        #expect(workflowPolicy.contains("  merge_group:"))
        #expect(
            appendJob.contains(
                "github.ref == 'refs/heads/main' && (github.event_name == 'push' || (github.event_name == 'workflow_dispatch' && needs.ci-plan.outputs.post_merge == 'true'))"
            )
        )
        #expect(appendJob.contains("always() && !cancelled()"))
        for job in ["ci-plan", "ci-required", "macro-tests"] {
            #expect(appendJob.contains("needs.\(job).result == 'success'"))
        }
        #expect(appendJob.contains("Verify performance history source context"))
        #expect(appendJob.contains("INNODI_PERF_EXPECTED_SHA: ${{ github.sha }}"))
        // The additional dispatch path must prove an actual merged bot at
        // current main before it can reuse main's publication/history contract.
        #expect(appendJob.contains("      - ci-plan\n"))
        #expect(workflow.contains("Verify actual post-merge main origin"))
        #expect(workflow.contains("verify-post-merge --pr \"$MERGED_PR\" --expected-sha \"$GITHUB_SHA\""))
        #expect(workflow.contains("publish_pages: ${{ needs.ci-plan.outputs.post_merge == 'true' }}"))
    }

    @Test("Main CI keeps an explicit Xcode 27 compatibility lane")
    func xcode27CompatibilityLane() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let jobStart = try #require(
            workflow.range(of: "  xcode-27-compatibility:\n")
        )
        let nextJobStart = try #require(
            workflow.range(
                of: "\n  apple-platform-builds:\n",
                range: jobStart.upperBound..<workflow.endIndex
            )
        )
        let job = workflow[jobStart.lowerBound..<nextJobStart.lowerBound]

        #expect(job.contains("name: Xcode 27 compatibility preview"))
        #expect(job.contains("runs-on: xcode-27"))
        #expect(job.contains("Apple Swift version 6.4"))
        #expect(job.contains("--filter StrictConcurrencyBuildTests"))
        #expect(job.contains("--filter ExternalConsumerContractTests"))
        #expect(job.contains("Tools/check-public-api.py"))
    }

    @Test("CI caches stay toolchain-scoped and release validation stays cold")
    func cachesAreToolchainScoped() throws {
        let root = packageRootURL()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let cacheSteps = workflow.components(separatedBy: "      - name: ").filter {
            $0.contains("uses: actions/cache@")
        }
        #expect(cacheSteps.count == 8)
        for step in cacheSteps {
            #expect(step.contains("key: ${{ steps.cache-inputs.outputs."))
            #expect(!step.contains("hashFiles('Package.resolved')"))
            #expect(!step.contains("restore-keys"))
        }
        let consumerSteps = cacheSteps.filter {
            $0.contains("path: ${{ steps.cache-inputs.outputs.consumer-paths }}")
        }
        #expect(consumerSteps.count == 3)
        for step in consumerSteps {
            #expect(step.contains("key: ${{ steps.cache-inputs.outputs.consumer-key }}"))
        }
        #expect(workflow.components(separatedBy: "run: python3 -B Tools/ci-cache.py fingerprint").count - 1 == 5)
        #expect(workflow.components(separatedBy: "run: python3 -B Tools/ci-cache.py restored").count - 1 == 5)
        #expect(workflow.components(separatedBy: "run: python3 -B Tools/ci-cache.py report").count - 1 == 5)
        // Execute exact compiler/build/pin/profile collision and empty-input
        // controls, rather than assuming distinct literal Xcode labels are
        // sufficient cache identity. Also pins exhaustive as a fast superset.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", "Tools/tests/test_ci_cache.py"]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        // Release validation keeps cold consumer builds for the exact candidate.
        #expect(!release.contains("actions/cache@"))
    }

    @Test("Compiler canaries stay informational and hidden from repository scans")
    func compilerCanariesAreInformational() throws {
        let root = packageRootURL()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let minimumStart = try #require(workflow.range(of: "  swift-62-compatibility:\n"))
        let previewStart = try #require(workflow.range(of: "  xcode-27-compatibility:\n"))
        let platformStart = try #require(workflow.range(of: "  apple-platform-builds:\n"))
        let minimumJob = workflow[minimumStart.lowerBound..<previewStart.lowerBound]
        let previewJob = workflow[previewStart.lowerBound..<platformStart.lowerBound]

        #expect(minimumJob.contains("- name: Report compiler canaries (informational)"))
        #expect(
            minimumJob.contains(
                "if: ${{ always() && github.event_name == 'workflow_dispatch' }}"
            )
        )
        #expect(previewJob.contains("- name: Report compiler canaries (informational)"))
        #expect(previewJob.contains("run: Tools/run-compiler-canaries.sh"))
        #expect(!workflow.contains("run-compiler-canaries.sh\n        continue-on-error"))

        let script = try String(
            contentsOf: root.appendingPathComponent("Tools/run-compiler-canaries.sh"),
            encoding: .utf8
        )
        #expect(script.contains("A canary result never fails the job."))

        let canaries = root.appendingPathComponent("Tests/CompilerCanaries")
        let enumerator = try #require(
            FileManager.default.enumerator(at: canaries, includingPropertiesForKeys: nil)
        )
        var fixtureCount = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            #expect(!name.hasSuffix(".swift"), "canary source must use a .fixture suffix: \(name)")
            if name.hasSuffix(".fixture") { fixtureCount += 1 }
        }
        #expect(fixtureCount >= 4)
    }

    @Test("Mutable action revisions are rejected")
    func mutableActionRevisionFails() throws {
        let fixture = try CIWorkflowFixture(
            additionalStep: "      - uses: actions/upload-artifact@v4\n"
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 1)
        #expect(result.output.contains("revision is not a full lowercase commit SHA"))
        #expect(result.output.contains("actions/upload-artifact@v4"))
    }

    @Test("Read-only checkout cannot persist credentials")
    func persistedReadOnlyCheckoutFails() throws {
        let fixture = try CIWorkflowFixture(checkoutPersistence: "true")
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 1)
        #expect(result.output.contains("persist-credentials: false"))
    }

    @Test("Every workflow must declare minimum top-level permissions")
    func missingPermissionsFail() throws {
        let fixture = try CIWorkflowFixture(includePermissions: false)
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 1)
        #expect(result.output.contains("top-level permissions must be exactly contents: read"))
    }

    @Test("Unreviewed job-level write permissions are rejected")
    func unreviewedJobPermissionsFail() throws {
        let fixture = try CIWorkflowFixture(
            additionalStep: """
              elevated:
                permissions:
                  contents: write
                runs-on: ubuntu-latest
                steps: []

            """
        )
        defer { fixture.remove() }

        let result = try fixture.run()

        #expect(result.exitCode == 1)
        #expect(result.output.contains("reviewed least-privilege map"))
    }

    @Test("Pages write and identity permissions belong only to deploy job")
    func pagesPermissionsAreJobScoped() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/docs.yml"),
            encoding: .utf8
        )
        let topLevel = try #require(workflow.range(of: "permissions:\n"))
        let jobs = try #require(workflow.range(of: "\njobs:\n"))
        let topLevelPermissions = workflow[topLevel.lowerBound..<jobs.lowerBound]
        let deployStart = try #require(workflow.range(of: "  deploy-pages:\n"))
        let deployJob = workflow[deployStart.lowerBound...]

        #expect(topLevelPermissions.contains("  contents: read"))
        #expect(!topLevelPermissions.contains("pages: write"))
        #expect(!topLevelPermissions.contains("id-token: write"))
        #expect(deployJob.contains("    permissions:\n      pages: write\n      id-token: write"))
    }

    @Test("Renamed-checkout CI uses representative contracts instead of repeating full matrices")
    func pathIdentityJobStaysTargeted() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let jobStart = try #require(workflow.range(of: "  path-identity:\n"))
        let job = workflow[jobStart.lowerBound...]

        #expect(job.contains("    timeout-minutes: 30"))
        #expect(job.contains("INNODI_EXTERNAL_FIXTURE: basic-container"))
        #expect(
            job.contains(
                "--filter StrictConcurrencyBuildTests.swiftUIMainActorRootBuildsUnderStrictConcurrency"
            )
        )
        #expect(
            job.contains(
                "--filter ExternalConsumerContractTests.compilePassFixturesBuild"
            )
        )
        #expect(!job.contains("--filter StrictConcurrencyBuildTests\n"))
        #expect(!job.contains("--filter ExternalConsumerContractTests\n"))
        #expect(job.contains("swift build --scratch-path \"$scratch_path\""))
        #expect(job.contains("cd Examples/SampleApp && swift test --scratch-path \"$scratch_path\""))
        #expect(job.contains("swift run --scratch-path \"$scratch_path\" --skip-build SampleApp"))
    }

    @Test("Main CI measures macro performance once and appends history on Ubuntu")
    func macroPerformanceMeasurementIsReused() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let measurementCount = workflow.components(
            separatedBy: "Tools/measure-macro-performance.sh"
        ).count - 1
        let appendStart = try #require(
            workflow.range(of: "  append-perf-history:\n")
        )
        let appendJob = workflow[appendStart.lowerBound...]

        #expect(measurementCount == 1)
        #expect(workflow.contains("--output build/macro-performance-report.json"))
        #expect(workflow.contains("        id: macro_performance"))
        #expect(
            workflow.contains(
                "if: ${{ always() && steps.macro_performance.outcome != 'skipped' }}"
            )
        )
        #expect(
            workflow.contains(
                "--current-report build/macro-performance-report.json"
            )
        )
        #expect(appendJob.contains("    runs-on: ubuntu-latest"))
        #expect(appendJob.contains("      contents: write"))
        #expect(appendJob.contains("--report build/performance/macro-performance-report.json"))
    }

    @Test("Fast PR lane and coverage gate publish test suite durations")
    func testSuiteDurationsAreSummarized() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-B", "-m", "unittest", "discover",
            "-s", "Tools/tests", "-p", "test_summarize_test_durations.py",
        ]
        process.currentDirectoryURL = packageRootURL()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/macro-tests.yml"),
            encoding: .utf8
        )
        let fastStart = try #require(workflow.range(of: "  fast-tests:\n"))
        let exhaustiveStart = try #require(workflow.range(of: "  macro-tests:\n"))
        let fastJob = workflow[fastStart.lowerBound..<exhaustiveStart.lowerBound]
        #expect(fastJob.contains("set -o pipefail"))
        #expect(fastJob.contains("2>&1 | tee build/fast-pr-test-output.log"))
        #expect(fastJob.contains("- name: Summarize test suite durations"))
        #expect(
            fastJob.contains(
                "if: ${{ always() && hashFiles('build/fast-pr-test-output.log') != '' }}"
            )
        )

        let coverageGate = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent("Tools/run-coverage-gate.sh"),
            encoding: .utf8
        )
        #expect(coverageGate.contains("trap summarize_test_durations EXIT"))
        #expect(coverageGate.contains("2>&1 | tee \"$TEST_LOG\""))
        #expect(coverageGate.contains("Tools/summarize-test-durations.py"))
    }

    @Test("Independent performance checks survive failure without weakening the job")
    func performanceFailureDoesNotSuppressOtherEvidence() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "Tools/tests/test_performance_workflow.py"]
        process.currentDirectoryURL = packageRootURL()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }

    @Test("Independent feature reports reject incomplete evidence without replacing the calibrated gate")
    func featurePerformanceEvidenceIsIndependent() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-B", "Tools/tests/test_macro_feature_report.py"]
        process.currentDirectoryURL = packageRootURL()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let workflow = try String(contentsOf: packageRootURL().appendingPathComponent(".github/workflows/macro-tests.yml"), encoding: .utf8)
        #expect(workflow.contains("run: Tools/measure-macro-features.sh"))
        #expect(workflow.contains("name: macro-feature-performance-report"))
        #expect(workflow.contains("--enforce"))
    }

    @Test("Agent guidance follows the accepted grammar and calibrated measurement policy")
    func agentGuidanceMatchesCurrentContracts() throws {
        let guidance = try String(contentsOf: packageRootURL().appendingPathComponent("CLAUDE.md"), encoding: .utf8)
        #expect(guidance.contains("@DIContainerRole(role: ContainerRole.local, mainActor: true)"))
        #expect(guidance.contains("@Input(escaping: true)"))
        #expect(!guidance.contains("@Provide(.input"))
        #expect(!guidance.contains("@DIContainer(mainActor: true)"))
        #expect(!guidance.contains("10% threshold"))
        #expect(guidance.contains("minimum 5 comparable entries, 20% threshold"))
        #expect(guidance.contains("report-only-unbaselined"))
        #expect(guidance.contains("Perf History` is manual recovery"))
    }

    @Test("Agent guidance distinguishes version promotion from verified publication")
    func agentGuidanceRequiresPublicationEvidence() throws {
        let guidance = try String(
            contentsOf: packageRootURL().appendingPathComponent("CLAUDE.md"),
            encoding: .utf8
        ).split(whereSeparator: \.isWhitespace).joined(separator: " ")

        // Keep this invariant independent of the version being promoted and
        // Markdown line wrapping. Preparing metadata is not publication proof.
        #expect(guidance.contains("A version-promotion PR is not a published release"))
        #expect(guidance.contains("verify its exact-SHA release workflow and immutable GitHub Release before reporting publication"))
        #expect(guidance.contains("Do not claim release readiness from local tests, skip/insufficient-history statuses, or a green run for an older revision"))
    }

    @Test("Main CI leaves example builds to the plan-selected reusable matrix")
    func mainCIDoesNotDuplicateExampleBuilds() throws {
        let root = packageRootURL().appendingPathComponent(".github/workflows")
        let mainWorkflow = try String(
            contentsOf: root.appendingPathComponent("macro-tests.yml"),
            encoding: .utf8
        )
        let exampleWorkflow = try String(
            contentsOf: root.appendingPathComponent("examples.yml"),
            encoding: .utf8
        )
        let mainJobStart = try #require(mainWorkflow.range(of: "  macro-tests:\n"))
        let nextJobStart = try #require(
            mainWorkflow.range(of: "\n  swift-62-compatibility:\n")
        )
        let mainJob = mainWorkflow[
            mainJobStart.lowerBound..<nextJobStart.lowerBound
        ]

        #expect(!mainJob.contains("Build Extended Examples"))
        #expect(!mainJob.contains("cd Examples/SwiftUIExample"))
        #expect(!mainJob.contains("cd Examples/PreviewInjectionExample"))
        #expect(exampleWorkflow.contains("  workflow_call:"))
        #expect(mainWorkflow.contains("uses: ./.github/workflows/examples.yml"))
        #expect(mainWorkflow.contains("needs.ci-plan.outputs.examples_full"))
        #expect(exampleWorkflow.contains("name: Examples Required"))
        #expect(exampleWorkflow.contains("Build and Test SwiftUIExample"))
        #expect(exampleWorkflow.contains("Build and Test PreviewInjectionExample"))
        // The representative consumer runs on the primary consumer toolchain,
        // where SwiftSyntax 604.0.0 has a matching prebuilt.
        let sampleStart = try #require(exampleWorkflow.range(of: "  sample-app:\n"))
        let sampleEnd = try #require(exampleWorkflow.range(of: "  swiftui-example:\n"))
        let sampleJob = exampleWorkflow[sampleStart.lowerBound..<sampleEnd.lowerBound]
        #expect(sampleJob.contains("runs-on: xcode-27"))
        #expect(sampleJob.contains("Verify prebuilt-compatible Xcode 27 and Swift 6.4"))
        #expect(!sampleJob.contains("select-xcode"))
        #expect(
            exampleWorkflow.components(
                separatedBy: "if: github.event_name != 'pull_request'"
            ).count - 1 == 2
        )
    }

    @Test("Cold benchmark persists visible metrics and fails on missing artifacts")
    func coldBuildMetricsAreRequired() throws {
        let root = packageRootURL()
        let workflow = try String(
            contentsOf: root
                .appendingPathComponent(".github/workflows/cold-build-benchmark.yml"),
            encoding: .utf8
        )
        let benchmarkScript = try String(
            contentsOf: root.appendingPathComponent("Tools/cold-build-benchmark.sh"),
            encoding: .utf8
        )

        #expect(workflow.contains("build/benchmarks/cold-${{ matrix.scenario }}.json"))
        #expect(workflow.contains("scenario: consumer-xcode-26.5"))
        #expect(workflow.contains("scenario: consumer-xcode-26.6"))
        #expect(workflow.contains("scenario: consumer-xcode-27"))
        #expect(workflow.contains("runs-on: ${{ matrix.xcode == '27.0' && 'xcode-27' || 'macos-26' }}"))
        #expect(workflow.contains("expected_swift_syntax_mode: prebuilt"))
        #expect(workflow.contains("Verify expected SwiftSyntax mode"))
        #expect(workflow.contains("actual=\"$(jq -r '.swift_syntax_mode' \"$METRICS_PATH\")\""))
        #expect(workflow.contains("--build-log \"build/benchmarks/cold-${{ matrix.scenario }}.log\""))
        #expect(workflow.contains("path: build/benchmarks/"))
        #expect(workflow.contains("if-no-files-found: error"))
        #expect(!workflow.contains(".build-metrics"))
        #expect(benchmarkScript.contains("\"$BINDINGS\" 1>&2"))
        #expect(benchmarkScript.contains("\"swift_syntax_mode\""))
        #expect(benchmarkScript.contains("badResponseStatusCode(404)"))
        #expect(benchmarkScript.contains("SWIFT_VERSION_OUTPUT=$(swift --version 2>/dev/null)"))
        #expect(benchmarkScript.contains("XCODE_VERSION_OUTPUT=$(xcodebuild -version 2>/dev/null)"))
        #expect(!benchmarkScript.contains("--version 2>/dev/null | head"))
    }

    @Test("Remote consumer smoke resolves and runs the exact published main SHA")
    func remoteConsumerSmokeUsesExactRevision() throws {
        let root = packageRootURL()
        let workflow = try String(
            contentsOf: root
                .appendingPathComponent(".github/workflows/remote-consumer-smoke.yml"),
            encoding: .utf8
        )
        let fixture = try String(
            contentsOf: root
                .appendingPathComponent("Tests/RemoteConsumerSmoke/Package.swift.fixture"),
            encoding: .utf8
        )

        #expect(workflow.contains("INNODI_REVISION: ${{ inputs.revision || github.sha }}"))
        #expect(workflow.contains("INNODI_BRANCH_REF: ${{ inputs.branch_ref || github.ref }}"))
        #expect(workflow.contains("Package.resolved"))
        #expect(workflow.contains("swift run --package-path \"$INNODI_REMOTE_CONSUMER\" --skip-build MacroOnlyApp"))
        #expect(workflow.contains("swift run --package-path \"$INNODI_REMOTE_CONSUMER\" --skip-build ValidatedApp"))
        #expect(workflow.contains("cancel-in-progress: true"))
        // The exact-revision proof runs on the primary consumer toolchain.
        #expect(workflow.contains("runs-on: xcode-27"))
        #expect(workflow.contains("Verify prebuilt-compatible Xcode 27 and Swift 6.4"))
        #expect(!workflow.contains("select-xcode"))
        #expect(fixture.contains("revision: \"{{INNODI_REVISION}}\""))
        #expect(fixture.contains("https://github.com/InnoSquadCorp/InnoDI.git"))
        #expect(!fixture.contains(".package(path:"))
        #expect(fixture.contains("InnoDIDAGValidationPlugin"))
    }

    @Test("Standalone performance history workflow is manual recovery only")
    func performanceHistoryWorkflowDoesNotRunOnMainPush() throws {
        let workflow = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent(".github/workflows/perf-history.yml"),
            encoding: .utf8
        )
        let triggerStart = try #require(workflow.range(of: "on:\n"))
        let permissionsStart = try #require(workflow.range(of: "\npermissions:\n"))
        let triggers = workflow[
            triggerStart.lowerBound..<permissionsStart.lowerBound
        ]

        #expect(triggers.contains("workflow_dispatch:"))
        #expect(!triggers.contains("push:"))
        #expect(workflow.contains("    permissions:\n      contents: write"))
    }
}

private struct CIWorkflowFixture {
    let rootURL: URL

    init(
        checkoutPersistence: String = "false",
        includePermissions: Bool = true,
        additionalStep: String = ""
    ) throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-CIWorkflow-\(UUID().uuidString)",
            isDirectory: true
        )
        let workflowDirectory = rootURL
            .appendingPathComponent(".github/workflows", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workflowDirectory,
            withIntermediateDirectories: true
        )
        let permissions = includePermissions
            ? "permissions:\n  contents: read\n\n"
            : ""
        let workflow = """
        name: Fixture

        on: workflow_dispatch

        \(permissions)jobs:
          test:
            runs-on: ubuntu-latest
            steps:
              - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0
                with:
                  persist-credentials: \(checkoutPersistence)
              - uses: ./local-action
        \(additionalStep)
        """
        try workflow.write(
            to: workflowDirectory.appendingPathComponent("fixture.yml"),
            atomically: true,
            encoding: .utf8
        )
    }

    func run() throws -> CIActionPinCommandResult {
        try runCIActionPinCheck(arguments: ["--root", rootURL.path])
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct CIActionPinCommandResult {
    let exitCode: Int32
    let output: String
}

private func runCIActionPinCheck(
    arguments: [String]
) throws -> CIActionPinCommandResult {
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "InnoDI-CIActionPins-\(UUID().uuidString).log"
    )
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
        packageRootURL()
            .appendingPathComponent("Tools/check-ci-action-pins.sh")
            .path,
    ] + arguments
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "GIT_DIR")
    environment.removeValue(forKey: "GIT_WORK_TREE")
    process.environment = environment

    try process.run()
    process.waitUntilExit()
    try outputHandle.synchronize()
    try outputHandle.close()

    return CIActionPinCommandResult(
        exitCode: process.terminationStatus,
        output: try String(contentsOf: outputURL, encoding: .utf8)
    )
}
