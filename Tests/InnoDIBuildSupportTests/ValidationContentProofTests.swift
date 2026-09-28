import Foundation
import Testing
@testable import InnoDIBuildSupport

extension ValidationCoordinatorTests {
    @Test("Equal size and mtime never prove unchanged source bytes", arguments: [false, true])
    func metadataPreservingContentChange(atomic: Bool) throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let file = fixture.rootURL.appendingPathComponent("Feature.swift")
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try touch(file, modifiedAt: stamp)
        let parser = MockValidationSyntaxParser()
        let collector = ValidationSignatureCollector(stateDirectoryPath: fixture.stateURL.path, parser: parser)
        let before = try collector.collectWithMetrics(rootPath: fixture.rootURL.path)
        let warm = try collector.collectWithMetrics(rootPath: fixture.rootURL.path)
        #expect(warm.signature == before.signature)
        #expect(parser.parseCount == 1)
        let oldBytes = try Data(contentsOf: file)
        let newBytes = Data("struct Feature { let value = 2 }\n".utf8)
        #expect(oldBytes.count == newBytes.count)
        try newBytes.write(to: file, options: atomic ? .atomic : [])
        try touch(file, modifiedAt: stamp)
        let after = try collector.collectWithMetrics(rootPath: fixture.rootURL.path)
        #expect(after.signature != before.signature)
        #expect(after.metrics.metadataCacheHitCount == 0)
        #expect(after.metrics.astReparseCount == 1)
        #expect(parser.parseCount == 2)
        let fresh = try collector.collectWithMetrics(rootPath: fixture.rootURL.path, useManifestCache: false)
        #expect(after.signature == fresh.signature)
    }

    @Test("Coordinator rejects metadata-preserving custom init just like a fresh cache")
    func metadataPreservingCustomInitCannotReuseSuccess() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        try "@DIContainer struct App {}".write(
            to: fixture.rootURL.appendingPathComponent("Container.swift"), atomically: true, encoding: .utf8
        )
        let file = fixture.rootURL.appendingPathComponent("Extension.swift")
        let valid = "extension App { func noop() {} }\n"
        let invalid = "extension App { init() {}      }\n"
        #expect(valid.utf8.count == invalid.utf8.count)
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        try valid.write(to: file, atomically: true, encoding: .utf8)
        try touch(file, modifiedAt: stamp)
        let runner = MockValidationRunner(results: [.init(exitCode: 0, stdout: "", stderr: "")])
        func run(_ state: URL) async throws -> ValidationExecutionOutcome {
            try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path, toolPath: "/usr/bin/true",
                stateDirectoryPath: state.path, outputDirectoryPath: fixture.outputAURL.path, runner: runner
            )
        }
        let validResult = try await run(fixture.stateURL)
        #expect(validResult.result.exitCode == 0)
        try invalid.write(to: file, atomically: true, encoding: .utf8)
        try touch(file, modifiedAt: stamp)
        let cached = try await run(fixture.stateURL)
        let fresh = try await run(fixture.rootURL.appendingPathComponent("fresh-state"))
        #expect(cached.result.exitCode != 0)
        #expect(cached.result.exitCode == fresh.result.exitCode)
        #expect(cached.metricsArtifact.issues.map(\.code) == fresh.metricsArtifact.issues.map(\.code))
        #expect(cached.metricsArtifact.issues.contains { $0.code == "container.custom-init-unsupported" })
    }
}
