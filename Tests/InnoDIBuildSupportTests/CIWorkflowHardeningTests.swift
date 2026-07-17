import Foundation
import Testing

@Suite("CI workflow hardening contracts")
struct CIWorkflowHardeningTests {
    @Test("Repository workflows use pinned actions and scoped credentials")
    func repositoryWorkflowsPass() throws {
        let result = try runCIActionPinCheck(arguments: [])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("pinned external action use(s)"))
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
        #expect(
            workflow.contains(
                "--current-report build/macro-performance-report.json"
            )
        )
        #expect(appendJob.contains("    runs-on: ubuntu-latest"))
        #expect(appendJob.contains("      contents: write"))
        #expect(appendJob.contains("--report build/performance/macro-performance-report.json"))
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
              - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5
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
