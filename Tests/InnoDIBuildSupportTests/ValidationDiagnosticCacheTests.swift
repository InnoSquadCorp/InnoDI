import Foundation
import Testing

@testable import InnoDIBuildSupport

@Suite("Cached diagnostic source positions")
struct ValidationDiagnosticCacheTests {
    private func record(
        for result: ValidationCommandResult,
        content: String?, issues: [ValidationIssue] = []
    ) -> SharedValidationRunRecord {
        .init(liveRunMetrics: .init(customInitValidationMilliseconds: 0,
                                   semanticValidationMilliseconds: 0,
                                   hierarchyValidationMilliseconds: 0,
                                   dagValidationMilliseconds: 0),
              reasonCodes: [], issues: issues, sourceContentSignature: content,
              resultSignature: validationResultSignature(result))
    }

    @Test("Separate cache files never admit mixed result and record publications")
    func mixedGenerationRecordsFailClosed() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let paths = ValidationSharedRunPaths(stateDirectory: fixture.stateURL, sharedRunKey: "mixed")
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let old = ValidationCommandResult(exitCode: 1, stdout: "", stderr: "App.swift:2:1: error")
        let new = ValidationCommandResult(exitCode: 1, stdout: "", stderr: "App.swift:5:1: error")
        try persistResult(old, to: paths.result)
        try persistSharedRunRecord(record(for: new, content: "new"), to: paths.record)
        #expect(paths.loadCachedRun(sourceContentSignature: "new") == nil)
        try persistResult(new, to: paths.result)
        try persistSharedRunRecord(record(for: old, content: "old"), to: paths.record)
        #expect(paths.loadCachedRun(sourceContentSignature: "old") == nil)
        try persistSharedRunRecord(record(for: new, content: "new"), to: paths.record)
        #expect(paths.loadCachedRun(sourceContentSignature: "new")?.result == new)
    }

    @Test("Warnings and stderr bind to exact bytes even with a successful exit",
          arguments: ["warning", "stderr", "failure"])
    func diagnosticRecordsNeedContentEvidence(_ kind: String) throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let paths = ValidationSharedRunPaths(stateDirectory: fixture.stateURL, sharedRunKey: "diagnostic")
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let result = ValidationCommandResult(exitCode: kind == "failure" ? 1 : 0,
                                             stdout: "", stderr: kind == "stderr" ? "App.swift:2:1: warning" : "")
        let issues: [ValidationIssue] = kind == "warning"
            ? [.init(code: "test.warning", severity: .warning, message: "warning",
                     location: .init(filePath: "App.swift", line: 2, column: 1))] : []
        try persistResult(result, to: paths.result)
        for content in [nil, "old"] as [String?] {
            try persistSharedRunRecord(record(for: result, content: content, issues: issues), to: paths.record)
            #expect(paths.loadCachedRun(sourceContentSignature: "new") == nil)
        }
        try persistSharedRunRecord(record(for: result, content: "new", issues: issues), to: paths.record)
        #expect(paths.loadCachedRun(sourceContentSignature: "new")?.result == result)
    }

    @Test("Terminal lock reconciliation rejects diagnostics for earlier source bytes")
    func finalBackoffCannotAdmitStalePositions() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let file = fixture.rootURL.appendingPathComponent("Container.swift")
        try "\n\n@DIContainer struct App {}\nextension App { init() {} }\n".write(
            to: file, atomically: true, encoding: .utf8
        )
        let signature = try collectValidationSignature(rootPath: fixture.rootURL.path,
                                                       stateDirectoryPath: fixture.stateURL.path)
        let paths = ValidationSharedRunPaths(stateDirectory: fixture.stateURL,
                                             sharedRunKey: sharedRunCacheKey(for: signature))
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let policy = ValidationCoordinatorLockPolicy(maxWaitSeconds: 0.3, staleLockAgeSeconds: 0.1,
                                                     initialBackoffSeconds: 0.05, maxBackoffSeconds: 0.2)
        try persistJSON(ValidationCoordinatorLockMetadata(pid: 1111, createdAt: 30_000), to: paths.lock)
        let stale = ValidationCommandResult(exitCode: 1, stdout: "", stderr: "stale-line-sentinel")
        let staleRecord = record(for: stale, content: "earlier-bytes")
        let threshold = SleepThresholdState(threshold: policy.maxWaitSeconds)
        let directory = paths.directory
        let clock = ManualValidationCoordinatorClock(startUptime: 10, startDate: Date(timeIntervalSince1970: 30_000)) { interval in
            guard threshold.shouldTrigger(afterSleeping: interval) else { return }
            try! persistResult(stale, to: directory.appendingPathComponent("result.json"))
            try! persistSharedRunRecord(staleRecord, to: directory.appendingPathComponent("validation-metrics.json"))
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("lock"))
        }
        let runner = MockValidationRunner(results: [.init(exitCode: 0, stdout: "", stderr: "")])
        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path, toolPath: nil, stateDirectoryPath: fixture.stateURL.path,
            outputDirectoryPath: fixture.outputAURL.path, runner: runner, lockPolicy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [1111, 4242])
        )
        #expect(!outcome.wasCached)
        #expect(!outcome.result.stderr.contains("stale-line-sentinel"))
        #expect(outcome.metricsArtifact.issues.contains { $0.code == "container.custom-init-unsupported" && $0.location.line == 4 })
        #expect(clock.sleptDurations.count == 3)
        #expect(runner.invocationCount == 0)
    }

    @Test("Trivia-only movement refreshes diagnostics without changing semantic identity")
    func movedFailureDoesNotReuseOldCoordinates() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let file = fixture.rootURL.appendingPathComponent("Container.swift")
        let source = "@DIContainer struct App {}\nextension App { init() {} }\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let runner = MockValidationRunner(results: [.init(exitCode: 0, stdout: "ok", stderr: "")])
        func validate() async throws -> ValidationExecutionOutcome {
            try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path, toolPath: nil,
                stateDirectoryPath: fixture.stateURL.path,
                outputDirectoryPath: fixture.outputAURL.path, runner: runner
            )
        }
        let first = try await validate()
        let originalIssue = try #require(first.metricsArtifact.issues.first {
            $0.code == "container.custom-init-unsupported"
        })
        #expect(first.result.exitCode != 0)
        #expect(try await validate().wasCached)
        try ("\n\n// moved\n" + source).write(to: file, atomically: true, encoding: .utf8)
        let moved = try await validate()
        let movedIssue = try #require(moved.metricsArtifact.issues.first {
            $0.code == "container.custom-init-unsupported"
        })
        #expect(moved.signature == first.signature)
        #expect(!moved.wasCached)
        #expect(movedIssue.location.line == originalIssue.location.line + 3)
        #expect(movedIssue.location.column == originalIssue.location.column)
        #expect(moved.result.stderr != first.result.stderr)
        let repeatRead = try await validate()
        #expect(repeatRead.wasCached)
        #expect(repeatRead.result.stderr == moved.result.stderr)
        #expect(runner.invocationCount == 0)
    }

    @Test("Trivia-only changes still reuse a semantic success without diagnostics")
    func harmlessTriviaKeepsSuccessCache() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let file = fixture.rootURL.appendingPathComponent("Container.swift")
        let source = "@DIContainer struct App {}\n"
        try source.write(to: file, atomically: true, encoding: .utf8)
        let runner = MockValidationRunner(results: [.init(exitCode: 0, stdout: "ok", stderr: "")])
        func validate() async throws -> ValidationExecutionOutcome {
            try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path, toolPath: nil,
                stateDirectoryPath: fixture.stateURL.path,
                outputDirectoryPath: fixture.outputAURL.path, runner: runner
            )
        }
        let first = try await validate()
        #expect(first.result.exitCode == 0)
        #expect(first.metricsArtifact.issues.isEmpty)
        try ("// moved without semantic changes\n" + source).write(to: file, atomically: true, encoding: .utf8)
        let moved = try await validate()
        #expect(moved.signature == first.signature)
        #expect(moved.wasCached)
        #expect(runner.invocationCount == 1)
    }

    @Test("Relocated checkouts refresh source paths but retain location-free successes",
          arguments: [true, false])
    func movedRootRefreshesDiagnosticPaths(_ invalid: Bool) async throws {
        let original = try makeFixture()
        let relocated = try makeFixture()
        defer {
            try? FileManager.default.removeItem(at: original.rootURL)
            try? FileManager.default.removeItem(at: relocated.rootURL)
        }
        let source = "@DIContainer struct App {}\n"
            + (invalid ? "extension App { init() {} }\n" : "")
        for root in [original.rootURL, relocated.rootURL] {
            try source.write(to: root.appendingPathComponent("Container.swift"),
                             atomically: true, encoding: .utf8)
        }
        let runner = MockValidationRunner(results: [.init(exitCode: 0, stdout: "ok", stderr: "")])
        func validate(_ root: URL) async throws -> ValidationExecutionOutcome {
            try await ValidationCoordinator.coordinate(
                rootPath: root.path, toolPath: nil,
                stateDirectoryPath: original.stateURL.path,
                outputDirectoryPath: original.outputAURL.path, runner: runner
            )
        }
        let first = try await validate(original.rootURL)
        let moved = try await validate(relocated.rootURL)
        #expect(moved.signature == first.signature)
        if invalid {
            #expect(!moved.wasCached)
            let issue = try #require(moved.metricsArtifact.issues.first {
                $0.code == "container.custom-init-unsupported"
            })
            #expect(issue.location.filePath == relocated.rootURL.appendingPathComponent("Container.swift").path)
            #expect(!moved.result.stderr.contains(original.rootURL.path))
            #expect(try await validate(relocated.rootURL).wasCached)
            #expect(runner.invocationCount == 0)
        } else {
            #expect(moved.wasCached)
            #expect(moved.metricsArtifact.issues.isEmpty)
            #expect(runner.invocationCount == 1)
        }
    }
}
