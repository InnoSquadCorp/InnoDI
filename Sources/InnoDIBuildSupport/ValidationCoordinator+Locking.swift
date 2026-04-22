//
//  ValidationCoordinator+Locking.swift
//  InnoDIBuildSupport
//
//  Phase N-1 — extracted from `ValidationCoordinator.swift`.
//
//  POSIX-level cross-process locking + stale-lock recovery used by the
//  coordinator to serialize live DAG validation runs per signature. Also
//  hosts the small IO-adjacent utilities (process existence check, pipe
//  read-handler installer, thread-safe buffer, duration formatter) and the
//  two `LocalizedError` wrappers the lock path throws.
//
//  These helpers are strictly infrastructure — the orchestration logic in
//  `ValidationCoordinator.swift` composes them.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Lock primitives

internal func acquireLock(at url: URL) throws -> Int32? {
    let path = url.path(percentEncoded: false)
    let descriptor = open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)

    if descriptor >= 0 {
        return descriptor
    }

    if errno == EEXIST {
        return nil
    }

    throw POSIXLockError(code: errno, path: path)
}

internal func persistLockMetadata(
    _ metadata: ValidationCoordinatorLockMetadata,
    descriptor: Int32,
    path: String
) throws {
    let data = try JSONEncoder().encode(metadata)
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
    do {
        try handle.truncate(atOffset: 0)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: data)
        try handle.synchronize()
    } catch {
        throw ValidationCoordinatorIOError(path: path, operation: "write lock metadata", underlying: error)
    }
}

internal func loadLockMetadata(at url: URL) -> ValidationCoordinatorLockMetadata? {
    guard
        let data = try? Data(contentsOf: url),
        let metadata = try? JSONDecoder().decode(ValidationCoordinatorLockMetadata.self, from: data),
        metadata.pid > 0
    else {
        return nil
    }

    return metadata
}

internal func releaseLock(descriptor: Int32, at url: URL) {
    close(descriptor)
    try? FileManager.default.removeItem(at: url)
}

internal func recoverStaleLockIfNeeded(
    at url: URL,
    staleLockAgeSeconds: TimeInterval,
    runtime: ValidationCoordinatorRuntime
) throws -> Bool {
    let fileManager = FileManager.default
    let path = url.path(percentEncoded: false)

    guard fileManager.fileExists(atPath: path) else {
        return false
    }

    let recoveryTokenURL = url.appendingPathExtension("recovering")
    guard let recoveryDescriptor = try acquireLock(at: recoveryTokenURL) else {
        return false
    }
    defer { releaseLock(descriptor: recoveryDescriptor, at: recoveryTokenURL) }

    guard fileManager.fileExists(atPath: path) else {
        return false
    }

    if let metadata = loadLockMetadata(at: url) {
        guard runtime.processExists(metadata.pid) == false else {
            return false
        }
        runtime.beforeStaleLockRemoval(url)
        try? fileManager.removeItem(at: url)
        return fileManager.fileExists(atPath: path) == false
    }

    guard
        let ageSeconds = lockFileAgeSeconds(at: path, now: runtime.currentDate()),
        ageSeconds >= staleLockAgeSeconds
    else {
        return false
    }

    runtime.beforeStaleLockRemoval(url)
    try? fileManager.removeItem(at: url)
    return fileManager.fileExists(atPath: path) == false
}

internal func lockFileAgeSeconds(at path: String, now: Date) -> TimeInterval? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
        return nil
    }

    let referenceDate = (attributes[.modificationDate] as? Date) ?? (attributes[.creationDate] as? Date)
    guard let referenceDate else {
        return nil
    }

    return max(0, now.timeIntervalSince(referenceDate))
}

// MARK: - Lock error types

internal struct POSIXLockError: LocalizedError {
    let code: Int32
    let path: String

    var errorDescription: String? {
        "Failed to acquire validation lock at '\(path)' (errno: \(code))."
    }
}

internal struct ValidationCoordinatorIOError: LocalizedError {
    let path: String
    let operation: String
    let underlying: Error

    var errorDescription: String? {
        "Failed to \(operation) at '\(path)': \(underlying.localizedDescription)"
    }
}

// MARK: - Process/IO utilities

internal final class LockedDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else {
            return
        }

        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }
}

internal func validationProcessExists(_ pid: Int32) -> Bool {
    guard pid > 0 else {
        return false
    }

    let result = kill(pid, 0)
    if result == 0 {
        return true
    }

    return errno == EPERM
}

internal func formatSeconds(_ value: TimeInterval) -> String {
    String(format: "%.2f", value)
}

internal func installReadHandler(on handle: FileHandle, buffer: LockedDataBuffer) {
    handle.readabilityHandler = { readableHandle in
        let chunk = readableHandle.availableData
        if chunk.isEmpty {
            readableHandle.readabilityHandler = nil
            return
        }

        buffer.append(chunk)
    }
}
