//
//  ValidationCoordinator+Locking.swift
//  InnoDIBuildSupport
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
// MARK: - Filesystem requirements
//
//  The lock relies on `O_CREAT | O_EXCL` for atomic creation. Local
//  filesystems (APFS, HFS+, ext4, btrfs, xfs) implement this correctly. On
//  network filesystems the story is different:
//
//  - NFSv3 does not guarantee atomic O_EXCL semantics; concurrent clients
//    can both believe they created the file. Use NFSv4 or a local scratch
//    directory.
//  - SMB/CIFS shares do not provide reliable O_EXCL atomicity at all and
//    are not supported.
//  - Docker/Kubernetes bind mounts inherit the semantics of the host
//    filesystem — if the host is local, they are safe.
//
//  If InnoDI's build plugin must run where the derived-data directory is
//  backed by a network share, set DERIVED_DATA / SPM's `--scratch-path` to
//  a local path, or accept that concurrent builds may report spurious
//  "could not acquire validation lock" errors.
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
    let path = url.path(percentEncoded: false)
    var shouldRemove = false
    var descriptorInfo = stat()

    if fstat(descriptor, &descriptorInfo) == 0 {
        var pathInfo = stat()
        shouldRemove = path.withCString { cPath in
            stat(cPath, &pathInfo) == 0
                && descriptorInfo.st_dev == pathInfo.st_dev
                && descriptorInfo.st_ino == pathInfo.st_ino
        }
    }

    if shouldRemove {
        try? FileManager.default.removeItem(at: url)
    }

    close(descriptor)
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
        // Boot-ID check wins over PID check whenever both sides have one:
        // a mismatching bootID means the holder belonged to an earlier
        // system session, so its PID is free to reuse regardless of
        // `processExists`. Legacy v1 metadata (bootID == nil) falls back
        // to PID-only liveness, identical to the old behavior.
        if let lockedBootID = metadata.bootID,
           let currentBootID = runtime.currentBootID(),
           lockedBootID != currentBootID
        {
            runtime.beforeStaleLockRemoval(url)
            try? fileManager.removeItem(at: url)
            return fileManager.fileExists(atPath: path) == false
        }

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
        let name = errnoName(code)
        let base = "Failed to acquire validation lock at '\(path)' (errno: \(code) \(name))."
        if let hint = errnoActionHint(code) {
            return "\(base) \(hint)"
        }
        return base
    }
}

/// Maps a POSIX `errno` value to its symbolic name. Falls back to "unknown" so
/// the message stays informative even if Darwin/Glibc adds new codes.
internal func errnoName(_ code: Int32) -> String {
    switch code {
    case EACCES: return "EACCES"
    case EROFS:  return "EROFS"
    case ENOSPC: return "ENOSPC"
    case ENOENT: return "ENOENT"
    case EISDIR: return "EISDIR"
    case ENAMETOOLONG: return "ENAMETOOLONG"
    case ENOTDIR: return "ENOTDIR"
    case EEXIST: return "EEXIST"
    case EBUSY:  return "EBUSY"
    case EIO:    return "EIO"
    default:     return "unknown"
    }
}

/// Returns a one-line, actionable hint for a subset of well-known `errno`s
/// the lock-acquisition path can encounter. Returns `nil` for codes where a
/// generic message is already enough.
///
/// See `Sources/InnoDI/InnoDI.docc/lock-safety.md` for the full
/// troubleshooting guide.
internal func errnoActionHint(_ code: Int32) -> String? {
    switch code {
    case EACCES, EROFS:
        return "The directory is read-only or this process lacks write permission. " +
               "Set SPM `--scratch-path` (or DerivedData) to a writable, local filesystem."
    case ENOSPC:
        return "The filesystem is out of space. Free space on the lock directory's volume."
    case ENOENT, ENOTDIR:
        return "The lock directory does not exist. Re-run with a fresh build, or supply " +
               "`--scratch-path` to a directory that exists."
    default:
        return nil
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

// MARK: - Diagnostic rendering

/// Renders the stderr message used when the coordinator gives up waiting for
/// the validation lock. The previous version printed only the path and the
/// elapsed wait — users had to inspect lock files manually to find the
/// holder, the holder's age, and which env var to tune. This rendering folds
/// all of that into a single block, plus links to the lock-safety DocC
/// article.
internal func lockTimeoutDiagnosticMessage(
    lockURL: URL,
    lockPolicy: ValidationCoordinatorLockPolicy,
    recoveredStaleLock: Bool,
    runtime: ValidationCoordinatorRuntime
) -> String {
    let path = lockURL.path(percentEncoded: false)
    var lines: [String] = []
    lines.append("Timed out waiting for the InnoDI validation coordinator lock.")
    lines.append("  path:        \(path)")
    lines.append("  waited:      \(formatSeconds(lockPolicy.maxWaitSeconds))s")
    if recoveredStaleLock {
        lines.append("  note:        a stale lock was recovered during this run, but contention persisted afterwards.")
    }

    if let metadata = loadLockMetadata(at: lockURL) {
        lines.append("  holder pid:  \(metadata.pid)")
        if let age = lockFileAgeSeconds(at: path, now: runtime.currentDate()) {
            lines.append("  holder age:  \(formatSeconds(age))s")
        }
        if let bootID = metadata.bootID {
            lines.append("  boot id:     \(bootID)")
        }
    } else {
        lines.append("  holder:      <metadata unavailable — lock file missing or unreadable>")
    }

    lines.append("")
    lines.append("Suggested actions:")
    lines.append("  1) Re-run the build. Concurrent SPM/Xcode invocations are the most common cause.")
    lines.append("  2) Increase the wait window: INNODI_LOCK_TIMEOUT=<seconds> swift build  (default 30).")
    lines.append("  3) Lower the stale threshold if the holder pid is dead: INNODI_STALE_LOCK_AGE=<seconds>.")
    lines.append("  4) Move SPM's scratch path off a network filesystem if the path above lives on NFS/SMB:")
    lines.append("     swift build --scratch-path /tmp/innodi-cache  (NFSv3 and SMB are not safe — see lock-safety.md).")
    lines.append("")
    lines.append("Reference: https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDI/InnoDI.docc/lock-safety.md")

    return lines.joined(separator: "\n") + "\n"
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
