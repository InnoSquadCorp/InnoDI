import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIBuildSupport

@Suite("Validation signature snapshot binding")
struct ValidationSnapshotBindingTests {
    @Test("Changing a cached source after hashing cannot cache success for invalid bytes")
    func lateSourceReplacementCannotPoisonSuccess() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let file = fixture.rootURL.appendingPathComponent("Container.swift")
        let invalid = "@DIContainer struct App {}\nextension App { init() {} }\n"
        let valid = "@DIContainer struct App {}\n"
        try invalid.write(to: file, atomically: true, encoding: .utf8)
        let invalidSnapshot = try loadWorkspaceSourceSnapshot(rootPath: fixture.rootURL.path)
        let invalidReport = try CustomInitBuildValidator.validate(snapshot: invalidSnapshot)
        #expect(invalidReport.hasFailures)
        #expect(invalidReport.issues.contains { $0.code == "container.custom-init-unsupported" })
        let collector = ValidationSignatureCollector(
            stateDirectoryPath: fixture.stateURL.path,
            parser: LiveValidationSyntaxParser()
        )
        _ = try collector.collectOutput(rootPath: fixture.rootURL.path)
        let warm = try collector.collectOutput(rootPath: fixture.rootURL.path)
        #expect(warm.parsedSources.isEmpty)
        #expect(warm.result.metrics.metadataCacheHitCount == 2)
        let liveRunDirectory = fixture.stateURL.appendingPathComponent(
            sharedRunCacheKey(for: warm.result.signature), isDirectory: true
        )
        try FileManager.default.createDirectory(at: liveRunDirectory, withIntermediateDirectories: true)
        let liveLockURL = liveRunDirectory.appendingPathComponent("lock")
        let deadPID: Int32 = 1111
        try persistJSON(
            ValidationCoordinatorLockMetadata(pid: deadPID, createdAt: Date().timeIntervalSince1970),
            to: liveLockURL
        )
        let live = ValidationCoordinatorRuntime.live
        let runtime = ValidationCoordinatorRuntime(
            monotonicNow: live.monotonicNow,
            currentDate: live.currentDate,
            sleep: live.sleep,
            currentProcessID: live.currentProcessID,
            processExists: { $0 == deadPID ? false : live.processExists($0) },
            currentBootID: live.currentBootID,
            beforeStaleLockRemoval: { url in
                // Live-run recovery occurs after signature capture, even now
                // that signature.lock also records its own creation time.
                #expect(url == liveLockURL)
                try? valid.write(to: file, atomically: true, encoding: .utf8)
            }
        )
        let runner = MockValidationRunner(results: [.init(exitCode: 0, stdout: "", stderr: "")])
        let first = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path, toolPath: nil,
            stateDirectoryPath: fixture.stateURL.path,
            outputDirectoryPath: fixture.outputAURL.path,
            runner: runner, runtime: runtime
        )
        #expect(try String(contentsOf: file, encoding: .utf8) == valid)
        #expect(first.result.exitCode != 0)
        #expect(first.metricsArtifact.reasonCodes.contains(.staleLockRecovered))
        #expect(first.metricsArtifact.issues.contains { $0.code == "container.custom-init-unsupported" })
        #expect(runner.invocationCount == 0)
        try invalid.write(to: file, atomically: true, encoding: .utf8)
        let restored = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path, toolPath: nil,
            stateDirectoryPath: fixture.stateURL.path,
            outputDirectoryPath: fixture.outputBURL.path,
            runner: runner
        )
        #expect(restored.signature == first.signature)
        #expect(restored.result.exitCode != 0)
        #expect(restored.wasCached)
    }
    @Test("Retained root snapshots keep their bytes and source set after path changes")
    func rootSnapshotHasClosedSourceSet() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let collector = ValidationSignatureCollector(stateDirectoryPath: fixture.stateURL.path, parser: LiveValidationSyntaxParser())
        _ = try collector.collectOutput(rootPath: fixture.rootURL.path)
        let fresh = fixture.rootURL.appendingPathComponent("Fresh.swift")
        try "struct Fresh {}".write(to: fresh, atomically: true, encoding: .utf8)
        let capture = try collector.collectOutput(rootPath: fixture.rootURL.path)
        #expect(capture.parsedSources.count == 1)
        #expect(capture.capturedSourceBytes.count == 1)
        try FileManager.default.removeItem(at: fixture.rootURL.appendingPathComponent("Feature.swift"))
        try "struct Replaced {}".write(to: fresh, atomically: true, encoding: .utf8)
        try "struct Later {}".write(to: fixture.rootURL.appendingPathComponent("Later.swift"), atomically: true, encoding: .utf8)
        let snapshot = try loadWorkspaceSourceSnapshot(
            rootPath: fixture.rootURL.path,
            reusingParsedSources: capture.parsedSources,
            capturedSourceBytes: capture.capturedSourceBytes
        )
        #expect(snapshot.files.map(\.relativePath) == ["Feature.swift", "Fresh.swift"])
        #expect(snapshot.files[0].syntax.description.contains("struct Feature"))
        #expect(snapshot.files[1].syntax.description.contains("struct Fresh"))
    }

    @Test("Captured manifest snapshots reject missing or overlapping identities")
    func manifestSnapshotRequiresCompleteCapture() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let targetID = WorkspaceTargetID.swiftPM(packageIdentity: "fixture", moduleName: "App")
        let file = fixture.rootURL.appendingPathComponent("Feature.swift")
        let manifest = WorkspaceAnalysisManifest(
            rootPackageIdentity: "fixture", rootPackageDirectory: fixture.rootURL.path,
            primaryTargetID: targetID,
            targets: [WorkspaceAnalysisTarget(
                id: targetID, packageIdentity: "fixture", packageDisplayName: "Fixture",
                packageDirectory: fixture.rootURL.path, targetName: "App", moduleName: "App",
                kind: .generic, role: .primary,
                sources: [WorkspaceAnalysisSource(filePath: file.path, logicalPath: "Feature.swift", origin: .declared)],
                dependencies: []
            )]
        )
        let validated = try ValidatedWorkspaceAnalysisManifest(validating: manifest)
        let collector = ValidationSignatureCollector(stateDirectoryPath: fixture.stateURL.path, parser: LiveValidationSyntaxParser())
        let cold = try collector.collectOutput(validated: validated)
        let warm = try collector.collectOutput(validated: validated)
        #expect(warm.parsedSources.isEmpty && warm.capturedSourceBytes.count == 1)
        try "struct Replaced {}".write(to: file, atomically: true, encoding: .utf8)
        let snapshot = try loadWorkspaceSourceSnapshot(validated: validated, reusingParsedSources: warm.parsedSources, capturedSourceBytes: warm.capturedSourceBytes)
        #expect(snapshot.files[0].syntax.description.contains("struct Feature"))
        #expect(throws: WorkspaceSourceSnapshotError.self) {
            try loadWorkspaceSourceSnapshot(validated: validated, capturedSourceBytes: [:])
        }
        #expect(throws: WorkspaceSourceSnapshotError.self) {
            try loadWorkspaceSourceSnapshot(validated: validated, reusingParsedSources: cold.parsedSources, capturedSourceBytes: warm.capturedSourceBytes)
        }
    }

    @Test("External compatibility tools do not reuse or overwrite snapshot-bound results")
    func externalToolResultsStayUncached() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        func coordinate(_ tool: String?) async throws -> ValidationExecutionOutcome {
            try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path, toolPath: tool,
                stateDirectoryPath: fixture.stateURL.path, outputDirectoryPath: fixture.outputAURL.path
            )
        }
        let original = try await coordinate(nil)
        #expect(original.result.exitCode == 0 && !original.wasCached)
        let tool = fixture.rootURL.appendingPathComponent("external.sh")
        try "#!/bin/sh\nprintf 'first external marker\\n'\nexit 7\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let first = try await coordinate(tool.path)
        #expect(first.result.exitCode == 7 && first.result.stdout.contains("first external marker"))
        #expect(!first.wasCached && first.metricsArtifact.reasonCodes.contains(.externalToolUncached))
        try "#!/bin/sh\nprintf 'second external marker\\n'\nexit 9\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        let second = try await coordinate(tool.path)
        #expect(second.result.exitCode == 9 && second.result.stdout.contains("second external marker"))
        #expect(!second.wasCached)
        let cached = try await coordinate(nil)
        #expect(cached.result.exitCode == 0 && cached.wasCached)
        #expect(cached.result == original.result)
    }

    @Test("Root module metadata uses the captured Package.swift tree")
    func rootModuleGraphUsesCapturedManifest() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let manifest = fixture.rootURL.appendingPathComponent("Package.swift")
        try "let package = Package(name: \"Before\", targets: [.target(name: \"Before\")])".write(to: manifest, atomically: true, encoding: .utf8)
        let snapshot = try loadWorkspaceSourceSnapshot(rootPath: fixture.rootURL.path)
        try "let package = Package(name: \"After\", targets: [.target(name: \"After\")])".write(to: manifest, atomically: true, encoding: .utf8)
        let captured = ModuleGraphProvider.snapshot(sourceSnapshot: snapshot)
        let live = try ModuleGraphProvider.snapshot(rootPath: fixture.rootURL.path)
        #expect(captured.modules.map(\.name) == ["Before"])
        #expect(live.modules.map(\.name) == ["After"])
    }

}
