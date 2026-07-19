//
//  ValidationCoordinator+Locking.swift
//  InnoDIBuildSupport
//
//  POSIX-level cross-process locking + stale-lock recovery used by the
//  coordinator to serialize live DAG validation runs per signature. Also
//  hosts the small lock-adjacent utilities (process existence check, duration
//  formatter) and the two `LocalizedError` wrappers the lock path throws.
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
//  - NFS mounts are classified as unsafe because mount versions and lock
//    semantics cannot be reliably distinguished by the detector. Use a local
//    scratch directory, or opt in explicitly with INNODI_ALLOW_UNSAFE_LOCK=1.
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

/// Acquires the validation coordinator lock at `url`.
///
/// The lock is layered:
///   1. `open(O_CREAT | O_EXCL | O_RDWR)` — atomic creation on local
///      filesystems; the primary single-holder gate.
///   2. `flock(LOCK_EX | LOCK_NB)` — advisory exclusive lock on the
///      descriptor we just opened. Defense-in-depth on filesystems with
///      advisory-lock support, but it does not make filesystems classified
///      as unsafe supported by default. On safe filesystems the advisory lock
///      is redundant but cheap.
///
/// Returns:
/// - `nil` when either layer reports contention (`EEXIST` from
///   `open`, `EWOULDBLOCK`/`EAGAIN` from `flock`). The caller is
///   expected to retry with backoff or recover a stale lock.
/// - the file descriptor on success — the caller must release it
///   via `releaseLock(descriptor:at:)`.
///
/// Throws `POSIXLockError` for any other failure (`EACCES`,
/// `ENOSPC`, etc.) — see `errnoActionHint` for user-facing
/// suggestions per code.
internal func acquireLock(at url: URL) throws -> Int32? {
    let path = url.path(percentEncoded: false)
    let descriptor = open(path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)

    if descriptor < 0 {
        if errno == EEXIST {
            return nil
        }
        throw POSIXLockError(code: errno, path: path)
    }

    // Layer 2: advisory exclusive lock. Non-blocking so we can fold
    // contention into the same `nil` retry path the O_EXCL branch
    // uses — the caller's poll loop is the right place to retry.
    let flockResult = flock(descriptor, LOCK_EX | LOCK_NB)
    if flockResult != 0 {
        let flockErrno = errno
        close(descriptor)
        if flockErrno == EWOULDBLOCK || flockErrno == EAGAIN {
            return nil
        }
        throw POSIXLockError(code: flockErrno, path: path)
    }

    return descriptor
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

package func loadLockMetadata(at url: URL) -> ValidationCoordinatorLockMetadata? {
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

/// Reports whether the shared-run directory at `directoryURL` currently has a
/// live coordinator holding its `lock` file.
///
/// The probe opens the existing lock file (never creating one) and attempts a
/// non-blocking shared `flock`. A holder that acquired the lock via
/// `acquireLock(at:)` keeps `LOCK_EX` on the descriptor for the entire
/// validation run, so the shared probe fails with `EWOULDBLOCK` exactly while
/// the run is live. A crashed holder's `flock` is released by the kernel, so
/// its leftover lock file probes as unheld and the directory stays prunable.
///
/// Unexpected probe failures are treated as "held": wrongly skipping a prune
/// only leaves a directory for a later pass, while wrongly pruning a live
/// holder deletes artifacts mid-write.
internal func isSharedRunLockCurrentlyHeld(inDirectory directoryURL: URL) -> Bool {
    let lockPath = directoryURL
        .appendingPathComponent("lock")
        .path(percentEncoded: false)
    let descriptor = open(lockPath, O_RDWR)
    if descriptor < 0 {
        return errno != ENOENT
    }
    defer { close(descriptor) }

    if flock(descriptor, LOCK_SH | LOCK_NB) != 0 {
        return true
    }

    flock(descriptor, LOCK_UN)
    return false
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

// MARK: - Filesystem safety guard

/// Bundle returned by `checkLockFilesystemSafety` when the
/// coordinator must refuse to run. The tuple shape mirrors the
/// shared-run-record path so the caller can hand it directly to
/// `finalizeOutcome` without case-by-case plumbing.
internal struct UnsafeLockFilesystemOutcome {
    let result: ValidationCommandResult
    let record: SharedValidationRunRecord
}

/// Inspects the filesystem under `lockDirectory` and decides whether
/// the coordinator should proceed.
///
/// - Returns: `nil` to mean "proceed" (safe filesystem, or operator
///   explicitly opted-in via `INNODI_ALLOW_UNSAFE_LOCK`, or the
///   detector returned `.unknown` — in the unknown case a stderr
///   warning is emitted but the run continues so we never block on a
///   filesystem we don't yet recognize). A non-`nil` value means
///   "refuse" — the bundled `result` carries an `exitCode == 1` and a
///   structured stderr block that points users at lock-safety.md.
internal func checkLockFilesystemSafety(
    lockDirectory: URL,
    allowUnsafe: Bool
) -> UnsafeLockFilesystemOutcome? {
    let classification = FilesystemTypeDetector.classify(directory: lockDirectory)

    switch classification.safetyClass {
    case .safe:
        return nil

    case .unknown:
        // We don't recognize this filesystem; emit a one-line
        // warning to stderr and proceed. The user can re-run with
        // `INNODI_ALLOW_UNSAFE_LOCK=1` to silence the warning if
        // they wish, but it never blocks.
        if !allowUnsafe {
            let identifier = classification.identifier.isEmpty
                ? "<unavailable>"
                : classification.identifier
            let message = "InnoDI: lock directory '\(lockDirectory.path(percentEncoded: false))' is on an unrecognized filesystem (\(identifier)); proceeding optimistically. See lock-safety.md.\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        return nil

    case .unsafe:
        if allowUnsafe {
            let identifier = classification.identifier.isEmpty
                ? "<unavailable>"
                : classification.identifier
            let message = "InnoDI: INNODI_ALLOW_UNSAFE_LOCK=1 set; proceeding on unsafe filesystem (\(identifier)). Concurrent builds may corrupt the shared-run cache.\n"
            FileHandle.standardError.write(Data(message.utf8))
            return nil
        }
        let stderr = unsafeFilesystemDiagnosticMessage(
            lockDirectory: lockDirectory,
            classification: classification
        )
        let result = ValidationCommandResult(exitCode: 1, stdout: "", stderr: stderr)
        let record = SharedValidationRunRecord(
            liveRunMetrics: ValidationLiveRunMetrics(
                customInitValidationMilliseconds: 0,
                semanticValidationMilliseconds: 0,
                hierarchyValidationMilliseconds: 0,
                dagValidationMilliseconds: 0
            ),
            reasonCodes: [.unsafeFilesystem],
            issues: []
        )
        return UnsafeLockFilesystemOutcome(result: result, record: record)
    }
}

internal func unsafeFilesystemDiagnosticMessage(
    lockDirectory: URL,
    classification: FilesystemClassification
) -> String {
    let identifier = classification.identifier.isEmpty
        ? "<unavailable>"
        : classification.identifier
    var lines: [String] = []
    lines.append("InnoDI refuses to acquire its validation coordinator lock on this filesystem.")
    lines.append("  path:        \(lockDirectory.path(percentEncoded: false))")
    lines.append("  filesystem:  \(identifier) (classified as unsafe)")
    lines.append("")
    lines.append("Reason:")
    lines.append("  `O_CREAT | O_EXCL` is not reliable on NFS, SMB/CIFS, and some FUSE-backed")
    lines.append("  filesystems. Two concurrent builds can both believe they own the lock,")
    lines.append("  which would corrupt the shared-run validation cache.")
    lines.append("")
    lines.append("Suggested actions:")
    lines.append("  1) Move SPM's scratch path to a local filesystem:")
    lines.append("       swift build --scratch-path /tmp/innodi-cache")
    lines.append("  2) If you understand the risk and want to proceed anyway:")
    lines.append("       INNODI_ALLOW_UNSAFE_LOCK=1 swift build")
    lines.append("")
    lines.append("Reference: https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDI/InnoDI.docc/lock-safety.md")
    return lines.joined(separator: "\n") + "\n"
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
    lines.append("     swift build --scratch-path /tmp/innodi-cache  (NFS and SMB are not safe by default — see lock-safety.md).")
    lines.append("")
    lines.append("Reference: https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDI/InnoDI.docc/lock-safety.md")

    return lines.joined(separator: "\n") + "\n"
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
