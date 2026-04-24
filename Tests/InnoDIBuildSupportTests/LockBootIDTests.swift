import Foundation
import Testing

@testable import InnoDIBuildSupport

@Suite("Lock metadata boot-id semantics")
struct LockBootIDTests {
    @Test("Mismatching bootID forces stale recovery even when the PID is still alive")
    func staleRecoveryOnBootIDMismatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-lock-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockURL = tempDir.appendingPathComponent("validation.lock")
        let stalenessMetadata = ValidationCoordinatorLockMetadata(
            pid: 1, // init — guaranteed to exist on POSIX
            createdAt: Date().timeIntervalSince1970,
            bootID: 100
        )
        try JSONEncoder().encode(stalenessMetadata).write(to: lockURL)

        // Current boot ID differs from the recorded one, but the PID is
        // still alive. Without the boot-id check the lock would be
        // considered held; with it, the holder is known to belong to an
        // earlier system session.
        let runtime = ValidationCoordinatorRuntime(
            monotonicNow: { 0 },
            currentDate: { Date() },
            sleep: { _ in },
            currentProcessID: { 42 },
            processExists: { _ in true },
            currentBootID: { 200 },
            beforeStaleLockRemoval: { _ in }
        )

        let recovered = try recoverStaleLockIfNeeded(
            at: lockURL,
            staleLockAgeSeconds: 60,
            runtime: runtime
        )

        #expect(recovered)
        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)) == false)
    }

    @Test("Matching bootID with a live PID keeps the lock")
    func holdRespectsMatchingBootID() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-lock-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockURL = tempDir.appendingPathComponent("validation.lock")
        let liveMetadata = ValidationCoordinatorLockMetadata(
            pid: 1,
            createdAt: Date().timeIntervalSince1970,
            bootID: 123
        )
        try JSONEncoder().encode(liveMetadata).write(to: lockURL)

        let runtime = ValidationCoordinatorRuntime(
            monotonicNow: { 0 },
            currentDate: { Date() },
            sleep: { _ in },
            currentProcessID: { 42 },
            processExists: { _ in true },
            currentBootID: { 123 },
            beforeStaleLockRemoval: { _ in }
        )

        let recovered = try recoverStaleLockIfNeeded(
            at: lockURL,
            staleLockAgeSeconds: 60,
            runtime: runtime
        )

        #expect(recovered == false)
        #expect(FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)))
    }

    @Test("Legacy v1 metadata (no bootID) still falls back to PID-only liveness")
    func v1MetadataFallback() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-lock-boot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockURL = tempDir.appendingPathComponent("validation.lock")
        let legacyMetadata = ValidationCoordinatorLockMetadata(
            pid: 1,
            createdAt: Date().timeIntervalSince1970,
            bootID: nil
        )
        try JSONEncoder().encode(legacyMetadata).write(to: lockURL)

        // With bootID == nil, liveness is determined by processExists alone.
        let runtime = ValidationCoordinatorRuntime(
            monotonicNow: { 0 },
            currentDate: { Date() },
            sleep: { _ in },
            currentProcessID: { 42 },
            processExists: { _ in false },
            currentBootID: { 200 },
            beforeStaleLockRemoval: { _ in }
        )

        let recovered = try recoverStaleLockIfNeeded(
            at: lockURL,
            staleLockAgeSeconds: 60,
            runtime: runtime
        )

        #expect(recovered)
    }
}
