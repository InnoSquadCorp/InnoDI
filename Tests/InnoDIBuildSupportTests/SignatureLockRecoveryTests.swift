import Foundation
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIBuildSupport

@Suite("Signature cache lock recovery", .serialized)
struct SignatureLockRecoveryTests {
    @Test("Signature collection records its owner before parsing sources")
    func recordsOwnerBeforeCollectionAndRecoversDeadOwner() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let lockURL = fixture.stateURL.appendingPathComponent("signature.lock")
        let clock = ManualValidationCoordinatorClock(startUptime: 100, startDate: Date())
        let runtime = makeTestRuntime(clock: clock, currentPID: 1111, activePIDs: [1111])
        let parser = SignatureLockRecordingParser(lockURL: lockURL)
        let first = try await collectSignature(fixture, runtime: runtime, parser: parser)
        #expect(parser.lockData.count == 1)
        let data = try #require(parser.lockData.first.flatMap { $0 })
        let metadata = try JSONDecoder().decode(ValidationCoordinatorLockMetadata.self, from: data)
        #expect(metadata.pid == 1111)
        #expect(metadata.createdAt == clock.currentDate.timeIntervalSince1970)
        #expect(metadata.bootID == runtime.currentBootID())
        #expect(!FileManager.default.fileExists(atPath: lockURL.path))

        // Restore the exact persisted bytes as if the owner had exited before
        // releasing its lock. A fresh dead-owner lock needs no age-based wait.
        try data.write(to: lockURL)
        let second = try await collectSignature(
            fixture,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
        )
        #expect(first.result.signature == second.result.signature)
        #expect(clock.sleptDurations.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: lockURL.path))
    }

    @Test("A live signature-lock owner is not reclaimed based on age")
    func liveOwnerIsNotReclaimed() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let clock = ManualValidationCoordinatorClock(startUptime: 100, startDate: Date())
        let lockURL = fixture.stateURL.appendingPathComponent("signature.lock")
        let data = try JSONEncoder().encode(ValidationCoordinatorLockMetadata(
            pid: 1111, createdAt: clock.currentDate.addingTimeInterval(-120).timeIntervalSince1970
        ))
        try data.write(to: lockURL)
        try touch(lockURL, modifiedAt: clock.currentDate.addingTimeInterval(-120))
        let policy = ValidationCoordinatorLockPolicy(
            maxWaitSeconds: 0.15, staleLockAgeSeconds: 0.01,
            initialBackoffSeconds: 0.05, maxBackoffSeconds: 0.05
        )
        _ = try await collectSignature(
            fixture, policy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [1111, 4242])
        )
        #expect(clock.totalSlept >= policy.maxWaitSeconds - 0.000_001)
        #expect(try Data(contentsOf: lockURL) == data)
        #expect(!FileManager.default.fileExists(
            atPath: fixture.stateURL.appendingPathComponent("ast-digest-cache.json").path
        ))
    }

    @Test("Unreadable signature-lock metadata still uses the stale-age fallback")
    func unreadableMetadataUsesStaleAge() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let clock = ManualValidationCoordinatorClock(startUptime: 100, startDate: Date())
        let lockURL = fixture.stateURL.appendingPathComponent("signature.lock")
        try Data().write(to: lockURL)
        try touch(lockURL, modifiedAt: clock.currentDate)
        let policy = ValidationCoordinatorLockPolicy(
            maxWaitSeconds: 1, staleLockAgeSeconds: 0.1,
            initialBackoffSeconds: 0.05, maxBackoffSeconds: 0.05
        )
        _ = try await collectSignature(
            fixture, policy: policy,
            runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
        )
        #expect(clock.totalSlept >= policy.staleLockAgeSeconds)
        #expect(clock.totalSlept < policy.maxWaitSeconds)
        #expect(!FileManager.default.fileExists(atPath: lockURL.path))
        #expect(FileManager.default.fileExists(
            atPath: fixture.stateURL.appendingPathComponent("ast-digest-cache.json").path
        ))
    }

    @Test("A metadata write failure releases the signature lock before collection")
    func metadataFailureReleasesSignatureLock() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }
        let clock = ManualValidationCoordinatorClock(
            startUptime: 100, startDate: Date(timeIntervalSince1970: .nan)
        )
        do {
            _ = try await ValidationCoordinator.coordinate(
                rootPath: fixture.rootURL.path, toolPath: nil,
                stateDirectoryPath: fixture.stateURL.path,
                outputDirectoryPath: fixture.outputAURL.path,
                runner: InProcessValidationCommandRunner(),
                runtime: makeTestRuntime(clock: clock, currentPID: 4242, activePIDs: [4242])
            )
            Issue.record("Non-finite lock metadata must fail encoding")
        } catch is EncodingError {
            // JSONEncoder rejects the non-finite creation time.
        }
        let lockURL = fixture.stateURL.appendingPathComponent("signature.lock")
        #expect(!FileManager.default.fileExists(atPath: lockURL.path))
        #expect(!FileManager.default.fileExists(
            atPath: fixture.stateURL.appendingPathComponent("ast-digest-cache.json").path
        ))
        let descriptor = try #require(try acquireLock(at: lockURL))
        releaseLock(descriptor: descriptor, at: lockURL)
    }
}

private func collectSignature<Parser: ValidationSyntaxParsing>(
    _ fixture: FixturePaths,
    policy: ValidationCoordinatorLockPolicy = .default,
    runtime: ValidationCoordinatorRuntime,
    parser: Parser = LiveValidationSyntaxParser()
) async throws -> ValidationSignatureCollectionOutput {
    try await ValidationCoordinator.collectValidationSignatureWithSharedCacheLock(
        rootPath: fixture.rootURL.path, analysisManifest: nil,
        stateDirectoryURL: fixture.stateURL, stateDirectoryPath: fixture.stateURL.path,
        lockPolicy: policy, runtime: runtime, parser: parser
    )
}

private final class SignatureLockRecordingParser: @unchecked Sendable, ValidationSyntaxParsing {
    private let lock = NSLock()
    private let lockURL: URL
    private var captured: [Data?] = []

    init(lockURL: URL) { self.lockURL = lockURL }

    var lockData: [Data?] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func parse(source: String) -> SourceFileSyntax {
        let data = try? Data(contentsOf: lockURL)
        lock.lock()
        captured.append(data)
        lock.unlock()
        return Parser.parse(source: source)
    }
}
