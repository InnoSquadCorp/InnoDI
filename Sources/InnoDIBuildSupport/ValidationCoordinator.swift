import Foundation
import InnoDIDependencyGraphCore
import InnoDIWorkspaceAnalysis

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Captured stdout and stderr from a single DAG validation command run.
package struct ValidationCommandResult: Codable, Equatable, Sendable {
    package let exitCode: Int32
    package let stdout: String
    package let stderr: String

    package init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

/// Final coordinator output returned to the build plugin wrapper.
///
/// This bundles the raw command result with the normalized signature and the
/// per-invocation metrics artifact written alongside the plugin outputs.
package struct ValidationExecutionOutcome: Equatable, Sendable {
    package let result: ValidationCommandResult
    package let wasCached: Bool
    package let signature: String
    package let metricsArtifact: ValidationMetricsArtifact
    package let verboseSummary: String?
}

/// Abstraction over the DAG validation command so tests can inject deterministic
/// runners.
package protocol ValidationCommandRunning: Sendable {
    func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult
}

/// Shared record persisted for one live validation run keyed by the normalized
/// source signature.
package struct SharedValidationRunRecord: Codable, Equatable, Sendable {
    package let liveRunMetrics: ValidationLiveRunMetrics
    package let reasonCodes: [ValidationReasonCode]
    package let issues: [ValidationIssue]
}

package struct ValidationCoordinatorLockPolicy: Sendable {
    package static let `default` = Self()
    private static let maximumEnvironmentTimeIntervalSeconds: TimeInterval = 24 * 60 * 60

    /// Environment variable names honored by ``init(environment:warningHandler:)``.
    ///
    /// Keeping them as constants so tests and operators can reference them
    /// by name rather than hard-coding strings.
    package enum EnvKey {
        /// Seconds the coordinator is willing to wait for the live-validation lock.
        package static let lockTimeout = "INNODI_LOCK_TIMEOUT"
        /// Age in seconds past which a leftover lock file is treated as stale.
        package static let staleLockAge = "INNODI_STALE_LOCK_AGE"
        /// Set to `1`, `true`, or `yes` to bypass the filesystem safety
        /// guard and allow the coordinator to run on a filesystem where
        /// `O_CREAT | O_EXCL` is not reliable (NFS, SMB/CIFS, some FUSE).
        /// Use only when you accept that concurrent builds may corrupt
        /// the shared-run cache.
        package static let allowUnsafeLock = "INNODI_ALLOW_UNSAFE_LOCK"
    }

    package let maxWaitSeconds: TimeInterval
    package let staleLockAgeSeconds: TimeInterval
    package let initialBackoffSeconds: TimeInterval
    package let maxBackoffSeconds: TimeInterval
    package let allowUnsafeFilesystem: Bool

    package init(
        maxWaitSeconds: TimeInterval = 30,
        staleLockAgeSeconds: TimeInterval = 30,
        initialBackoffSeconds: TimeInterval = 0.05,
        maxBackoffSeconds: TimeInterval = 0.5,
        allowUnsafeFilesystem: Bool = false
    ) {
        self.maxWaitSeconds = maxWaitSeconds
        self.staleLockAgeSeconds = staleLockAgeSeconds
        self.initialBackoffSeconds = initialBackoffSeconds
        self.maxBackoffSeconds = maxBackoffSeconds
        self.allowUnsafeFilesystem = allowUnsafeFilesystem
    }

    /// Builds a policy, honoring environment-variable overrides for the two
    /// operator-relevant knobs.
    ///
    /// `INNODI_LOCK_TIMEOUT` and `INNODI_STALE_LOCK_AGE` accept a positive
    /// finite floating-point number of seconds up to 24 hours. Unparseable,
    /// non-positive, non-finite, or excessively large values fall back to the
    /// default and invoke `warningHandler` with a message explaining the
    /// fallback (default implementation writes to stderr) so the
    /// misconfiguration surfaces at the first build.
    package init(
        environment: [String: String],
        warningHandler: (String) -> Void = { message in
            FileHandle.standardError.write(Data("\(message)\n".utf8))
        }
    ) {
        let base = Self()
        let resolvedTimeout = Self.resolveTimeInterval(
            environment: environment,
            key: EnvKey.lockTimeout,
            fallback: base.maxWaitSeconds,
            warningHandler: warningHandler
        )
        let resolvedStale = Self.resolveTimeInterval(
            environment: environment,
            key: EnvKey.staleLockAge,
            fallback: base.staleLockAgeSeconds,
            warningHandler: warningHandler
        )

        let allowUnsafe = Self.resolveBool(
            environment: environment,
            key: EnvKey.allowUnsafeLock,
            fallback: false,
            warningHandler: warningHandler
        )

        self.init(
            maxWaitSeconds: resolvedTimeout,
            staleLockAgeSeconds: resolvedStale,
            initialBackoffSeconds: base.initialBackoffSeconds,
            maxBackoffSeconds: base.maxBackoffSeconds,
            allowUnsafeFilesystem: allowUnsafe
        )
    }

    private static func resolveBool(
        environment: [String: String],
        key: String,
        fallback: Bool,
        warningHandler: (String) -> Void
    ) -> Bool {
        guard let raw = environment[key] else { return fallback }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "1", "true", "yes", "y", "on": return true
        case "0", "false", "no", "n", "off", "": return false
        default:
            warningHandler(
                "InnoDI: ignoring invalid \(key)=\(raw); falling back to \(fallback)."
            )
            return fallback
        }
    }

    private static func resolveTimeInterval(
        environment: [String: String],
        key: String,
        fallback: TimeInterval,
        warningHandler: (String) -> Void
    ) -> TimeInterval {
        guard let raw = environment[key], !raw.isEmpty else {
            return fallback
        }
        guard let parsed = Double(raw),
              parsed.isFinite,
              parsed > 0,
              parsed <= maximumEnvironmentTimeIntervalSeconds else {
            warningHandler(
                "InnoDI: ignoring invalid \(key)=\(raw); falling back to \(fallback) seconds."
            )
            return fallback
        }
        return parsed
    }
}

package struct ValidationCoordinatorRuntime: Sendable {
    package static let live = Self(
        monotonicNow: validationNow,
        currentDate: Date.init,
        sleep: validationSleep,
        currentProcessID: { getpid() },
        processExists: validationProcessExists,
        currentBootID: BootIDProvider.live,
        beforeStaleLockRemoval: { _ in }
    )

    package let monotonicNow: @Sendable () -> TimeInterval
    package let currentDate: @Sendable () -> Date
    package let sleep: @Sendable (TimeInterval) async throws -> Void
    package let currentProcessID: @Sendable () -> Int32
    package let processExists: @Sendable (Int32) -> Bool
    /// Returns the current system boot ID, or `nil` if unavailable. The live
    /// implementation reads `sysctl kern.boottime` on Darwin and
    /// `/proc/stat btime` on Linux.
    package let currentBootID: @Sendable () -> Int64?
    package let beforeStaleLockRemoval: @Sendable (URL) async -> Void

    package init(
        monotonicNow: @escaping @Sendable () -> TimeInterval,
        currentDate: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        currentProcessID: @escaping @Sendable () -> Int32,
        processExists: @escaping @Sendable (Int32) -> Bool,
        currentBootID: @escaping @Sendable () -> Int64? = BootIDProvider.live,
        beforeStaleLockRemoval: @escaping @Sendable (URL) async -> Void = { _ in }
    ) {
        self.monotonicNow = monotonicNow
        self.currentDate = currentDate
        self.sleep = sleep
        self.currentProcessID = currentProcessID
        self.processExists = processExists
        self.currentBootID = currentBootID
        self.beforeStaleLockRemoval = beforeStaleLockRemoval
    }
}

/// Metadata persisted alongside a live validation lock file.
///
/// Schema versioning:
/// - v1 files only had `pid` and `createdAt`. They are still decodable via
///   the `bootID == nil` path and treated as stale so v2 writers never race
///   with v1 consumers.
/// - v2 adds `bootID` — the system boot time in seconds — so stale-detection
///   can distinguish a process from another with the same PID that started
///   after a reboot (Darwin: `sysctl kern.boottime`; Linux: `/proc/stat btime`).
package struct ValidationCoordinatorLockMetadata: Codable, Equatable, Sendable {
    package let pid: Int32
    package let createdAt: TimeInterval
    package let bootID: Int64?

    package init(pid: Int32, createdAt: TimeInterval, bootID: Int64? = nil) {
        self.pid = pid
        self.createdAt = createdAt
        self.bootID = bootID
    }
}

/// Resolves a monotonically-stable "session" identifier for the running system.
///
/// On Darwin this reads `kern.boottime` via `sysctl`. The value changes on
/// every reboot, so a persisted lock with a mismatching `bootID` is known
/// to belong to a previous session — i.e. its PID is safe to reuse.
///
/// Injected through `ValidationCoordinatorRuntime` so tests can simulate
/// reboots without actually rebooting the CI agent.
package enum BootIDProvider {
    package static func live() -> Int64? {
        #if canImport(Darwin)
        var boottime = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        let mibCount = u_int(mib.count)
        let status = mib.withUnsafeMutableBufferPointer { bufferPointer -> Int32 in
            sysctl(bufferPointer.baseAddress, mibCount, &boottime, &size, nil, 0)
        }
        guard status == 0 else { return nil }
        return Int64(boottime.tv_sec)
        #elseif canImport(Glibc)
        guard let contents = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else {
            return nil
        }
        for line in contents.split(separator: "\n") where line.hasPrefix("btime ") {
            let pieces = line.split(separator: " ")
            guard pieces.count == 2, let btime = Int64(pieces[1]) else { return nil }
            return btime
        }
        return nil
        #else
        return nil
        #endif
    }
}

// Version 9 preserves byte-stream hashing semantics across `combine` call
// boundaries. Keep validator and digest behavior in the cache salt so an
// unchanged workspace cannot reuse a result produced by an older contract.
package let sharedRunCacheVersion = 9

package func sharedRunCacheKey(for signature: String) -> String {
    "shared-run-v\(sharedRunCacheVersion)-\(signature)"
}

package func validationSleep(_ interval: TimeInterval) async throws {
    let maximumNanosecondInterval = TimeInterval(UInt64.max) / 1_000_000_000
    guard interval.isFinite, interval > 0, interval <= maximumNanosecondInterval else {
        return
    }

    let nanoseconds = UInt64((interval * 1_000_000_000).rounded(.up))
    try await Task.sleep(nanoseconds: nanoseconds)
}

/// Default process runner used by the coordinator to execute the DAG validator.
package struct InProcessValidationCommandRunner: ValidationCommandRunning {
    package init() {}

    package func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult {
        let result = validateDependencyGraph(snapshot: snapshot)
        return ValidationCommandResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
}

/// Compatibility process runner used by focused process-IO tests and by
/// package-internal callers that still need to exercise an external tool.
package struct LiveValidationCommandRunner: ValidationCommandRunning {
    package init() {}

    package func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult {
        guard let toolPath, !toolPath.isEmpty else {
            return try InProcessValidationCommandRunner().runValidationTool(
                toolPath: nil,
                rootPath: rootPath,
                snapshot: snapshot
            )
        }
        return try runValidationTool(toolPath: toolPath, rootPath: rootPath)
    }

    package func runValidationTool(toolPath: String, rootPath: String) throws -> ValidationCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["--root", rootPath, "--validate-dag"]
        process.currentDirectoryURL = URL(fileURLWithPath: rootPath)

        let fileManager = FileManager.default
        let tempDirectory = try makePrivateValidationProcessCaptureDirectory()
        let stdoutURL = tempDirectory.appendingPathComponent("stdout")
        let stderrURL = tempDirectory.appendingPathComponent("stderr")
        try createEmptyValidationProcessCaptureFile(at: stdoutURL)
        try createEmptyValidationProcessCaptureFile(at: stderrURL)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        var handlesClosed = false
        defer {
            if !handlesClosed {
                stdoutHandle.closeFile()
                stderrHandle.closeFile()
            }
        }
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        try process.run()
        process.waitUntilExit()

        stdoutHandle.closeFile()
        stderrHandle.closeFile()
        handlesClosed = true
        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ValidationCommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

private enum ValidationProcessCaptureError: Error {
    case failedToCreateCaptureFile(String)
}

private func makePrivateValidationProcessCaptureDirectory() throws -> URL {
    let fileManager = FileManager.default
    let url = fileManager.temporaryDirectory
        .appendingPathComponent("innodi-validation-output-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return url
}

private func createEmptyValidationProcessCaptureFile(at url: URL) throws {
    let path = url.path(percentEncoded: false)
    guard FileManager.default.createFile(
        atPath: path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
    ) else {
        throw ValidationProcessCaptureError.failedToCreateCaptureFile(path)
    }
}

/// Shared build-validation entry point.
///
/// The coordinator computes a source signature, reuses or produces one shared
/// live validation result per signature, and emits per-invocation metrics and
/// Markdown summaries for plugin consumers.
package enum ValidationCoordinator {
    package static func coordinate(
        rootPath: String,
        toolPath: String?,
        stateDirectoryPath: String,
        outputDirectoryPath: String,
        lockPolicy: ValidationCoordinatorLockPolicy = .default
    ) async throws -> ValidationExecutionOutcome {
        try await coordinate(
            rootPath: rootPath,
            toolPath: toolPath,
            stateDirectoryPath: stateDirectoryPath,
            outputDirectoryPath: outputDirectoryPath,
            runner: LiveValidationCommandRunner(),
            lockPolicy: lockPolicy
        )
    }

    /// Loads and validates an authoritative target manifest, isolates shared
    /// state by its stable primary target ID, and runs validation in process.
    /// A malformed manifest is terminal; this path never falls back to a root
    /// directory scan.
    package static func coordinate(
        analysisManifestPath: String,
        sharedStateDirectoryPath: String,
        outputDirectoryPath: String,
        lockPolicy: ValidationCoordinatorLockPolicy = .default
    ) async throws -> ValidationExecutionOutcome {
        let manifest = try loadWorkspaceAnalysisManifest(
            at: URL(fileURLWithPath: analysisManifestPath)
        )
        let stateDirectory = targetScopedValidationStateDirectory(
            for: manifest.primaryTargetID,
            under: URL(
                fileURLWithPath: sharedStateDirectoryPath,
                isDirectory: true
            )
        )
        return try await coordinate(
            manifest: manifest,
            stateDirectoryPath: stateDirectory.path(percentEncoded: false),
            outputDirectoryPath: outputDirectoryPath,
            runner: InProcessValidationCommandRunner(),
            lockPolicy: lockPolicy
        )
    }

    package static func coordinate<Runner: ValidationCommandRunning>(
        rootPath: String,
        toolPath: String?,
        stateDirectoryPath: String,
        outputDirectoryPath: String,
        runner: Runner,
        verboseLoggingEnabled: Bool = ValidationLogging.isVerboseEnabled(),
        lockPolicy: ValidationCoordinatorLockPolicy = .default,
        runtime: ValidationCoordinatorRuntime = .live
    ) async throws -> ValidationExecutionOutcome {
        try await coordinateResolved(
            rootPath: rootPath,
            analysisManifest: nil,
            toolPath: toolPath,
            stateDirectoryPath: stateDirectoryPath,
            outputDirectoryPath: outputDirectoryPath,
            runner: runner,
            verboseLoggingEnabled: verboseLoggingEnabled,
            lockPolicy: lockPolicy,
            runtime: runtime
        )
    }

    package static func coordinate<Runner: ValidationCommandRunning>(
        manifest: WorkspaceAnalysisManifest,
        stateDirectoryPath: String,
        outputDirectoryPath: String,
        runner: Runner,
        verboseLoggingEnabled: Bool = ValidationLogging.isVerboseEnabled(),
        lockPolicy: ValidationCoordinatorLockPolicy = .default,
        runtime: ValidationCoordinatorRuntime = .live
    ) async throws -> ValidationExecutionOutcome {
        let validatedManifest = try ValidatedWorkspaceAnalysisManifest(
            validating: manifest
        )
        return try await coordinateResolved(
            rootPath: validatedManifest.manifest.rootPackageDirectory,
            analysisManifest: validatedManifest,
            toolPath: nil,
            stateDirectoryPath: stateDirectoryPath,
            outputDirectoryPath: outputDirectoryPath,
            runner: runner,
            verboseLoggingEnabled: verboseLoggingEnabled,
            lockPolicy: lockPolicy,
            runtime: runtime
        )
    }

    private static func coordinateResolved<
        Runner: ValidationCommandRunning
    >(
        rootPath: String,
        analysisManifest: ValidatedWorkspaceAnalysisManifest?,
        toolPath: String?,
        stateDirectoryPath: String,
        outputDirectoryPath: String,
        runner: Runner,
        verboseLoggingEnabled: Bool,
        lockPolicy: ValidationCoordinatorLockPolicy,
        runtime: ValidationCoordinatorRuntime
    ) async throws -> ValidationExecutionOutcome {
        let coordinatorStartTime = validationNow()
        let fileManager = FileManager.default
        let stateDirectoryURL = URL(fileURLWithPath: stateDirectoryPath, isDirectory: true)
        let outputDirectoryURL = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)

        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        // Check the lock filesystem before signature collection. On unsafe
        // filesystems we still compute a one-shot signature for the emitted
        // metrics artifact, but we do not acquire signature.lock or write the
        // AST digest manifest.
        let unsafeFilesystemOutcome = checkLockFilesystemSafety(
            lockDirectory: stateDirectoryURL,
            allowUnsafe: lockPolicy.allowUnsafeFilesystem
        )

        let signatureCollectionStartTime = validationNow()
        let signatureCollectionOutput: ValidationSignatureCollectionOutput
        if unsafeFilesystemOutcome != nil {
            if let analysisManifest {
                signatureCollectionOutput = try collectValidationSignatureOutput(
                    validated: analysisManifest,
                    stateDirectoryPath: stateDirectoryPath,
                    persistManifestUpdates: false,
                    useManifestCache: false
                )
            } else {
                signatureCollectionOutput = try collectValidationSignatureOutput(
                    rootPath: rootPath,
                    stateDirectoryPath: stateDirectoryPath,
                    persistManifestUpdates: false,
                    useManifestCache: false
                )
            }
        } else {
            signatureCollectionOutput = try await collectValidationSignatureWithSharedCacheLock(
                rootPath: rootPath,
                analysisManifest: analysisManifest,
                stateDirectoryURL: stateDirectoryURL,
                stateDirectoryPath: stateDirectoryPath,
                lockPolicy: lockPolicy,
                runtime: runtime
            )
        }
        let signatureCollection = signatureCollectionOutput.result
        let outcomeWriter = ValidationOutcomeWriter(
            signatureCollection: signatureCollection,
            signatureCollectionMilliseconds: validationElapsedMilliseconds(
                since: signatureCollectionStartTime
            ),
            coordinatorStartTime: coordinatorStartTime,
            outputDirectory: outputDirectoryURL,
            verboseLoggingEnabled: verboseLoggingEnabled
        )

        if let unsafeFilesystemOutcome {
            return try outcomeWriter.finalize(
                result: unsafeFilesystemOutcome.result,
                wasCached: false,
                sharedRunRecord: unsafeFilesystemOutcome.record
            )
        }

        let sharedRunKey = sharedRunCacheKey(
            for: signatureCollection.signature
        )
        let paths = ValidationSharedRunPaths(
            stateDirectory: stateDirectoryURL,
            sharedRunKey: sharedRunKey
        )
        try fileManager.createDirectory(
            at: paths.directory,
            withIntermediateDirectories: true
        )
        try pruneSharedRunDirectories(
            keepingDirectoryName: sharedRunKey,
            in: stateDirectoryURL
        )

        if let cachedRun = paths.loadCachedRun() {
            return try outcomeWriter.finalize(
                result: cachedRun.result,
                wasCached: true,
                sharedRunRecord: cachedRun.record
            )
        }

        let executor = ValidationLockedRunExecutor(
            rootPath: rootPath,
            analysisManifest: analysisManifest,
            toolPath: toolPath,
            runner: runner,
            runtime: runtime,
            signatureCollectionOutput: signatureCollectionOutput,
            paths: paths,
            outcomeWriter: outcomeWriter
        )
        return try await ValidationSharedRunResolver(
            executor: executor,
            outcomeWriter: outcomeWriter,
            paths: paths,
            lockPolicy: lockPolicy,
            runtime: runtime
        ).resolve()
    }

    /// Serializes access to the AST digest manifest used by signature
    /// collection.
    ///
    /// Build-tool plugins are instantiated once per target. Without this
    /// best-effort lock, many target-level coordinator processes can all
    /// discover the same cold manifest and reparse the whole workspace before
    /// the live DAG-validation lock has a chance to share the result. The live
    /// run was already serialized; this lock moves the expensive signature
    /// cache warm-up into the same shape so later target invocations usually
    /// hit metadata-only cache paths instead of doing duplicate AST work.
    private static func collectValidationSignatureWithSharedCacheLock(
        rootPath: String,
        analysisManifest: ValidatedWorkspaceAnalysisManifest?,
        stateDirectoryURL: URL,
        stateDirectoryPath: String,
        lockPolicy: ValidationCoordinatorLockPolicy,
        runtime: ValidationCoordinatorRuntime
    ) async throws -> ValidationSignatureCollectionOutput {
        func collectSignature(
            persistManifestUpdates: Bool = true,
            useManifestCache: Bool = true
        ) throws -> ValidationSignatureCollectionOutput {
            if let analysisManifest {
                return try collectValidationSignatureOutput(
                    validated: analysisManifest,
                    stateDirectoryPath: stateDirectoryPath,
                    persistManifestUpdates: persistManifestUpdates,
                    useManifestCache: useManifestCache
                )
            }
            return try collectValidationSignatureOutput(
                rootPath: rootPath,
                stateDirectoryPath: stateDirectoryPath,
                persistManifestUpdates: persistManifestUpdates,
                useManifestCache: useManifestCache
            )
        }

        guard shouldSerializeSignatureCollection(
            stateDirectoryURL: stateDirectoryURL
        ) else {
            return try collectSignature(
                persistManifestUpdates: false,
                useManifestCache: false
            )
        }

        let lockURL = stateDirectoryURL.appendingPathComponent("signature.lock")
        let lockAcquisitionDeadline = runtime.monotonicNow() + lockPolicy.maxWaitSeconds
        var backoffSeconds = lockPolicy.initialBackoffSeconds

        while runtime.monotonicNow() < lockAcquisitionDeadline {
            if let descriptor = try acquireLock(at: lockURL) {
                defer { releaseLock(descriptor: descriptor, at: lockURL) }
                return try collectSignature()
            }

            if try await recoverStaleLockIfNeeded(
                at: lockURL,
                staleLockAgeSeconds: lockPolicy.staleLockAgeSeconds,
                runtime: runtime
            ) {
                backoffSeconds = lockPolicy.initialBackoffSeconds
                continue
            }

            let remainingWait = lockAcquisitionDeadline - runtime.monotonicNow()
            guard remainingWait > 0 else {
                break
            }

            let delaySeconds = min(backoffSeconds, remainingWait)
            try await runtime.sleep(delaySeconds)
            backoffSeconds = min(backoffSeconds * 2, lockPolicy.maxBackoffSeconds)
        }

        FileHandle.standardError.write(
            Data(
                "InnoDI: timed out waiting for the signature cache lock; collecting a one-shot source signature without using the manifest cache.\n"
                    .utf8
            )
        )
        return try collectSignature(
            persistManifestUpdates: false,
            useManifestCache: false
        )
    }

    private static func shouldSerializeSignatureCollection(
        stateDirectoryURL: URL
    ) -> Bool {
        let classification = FilesystemTypeDetector.classify(directory: stateDirectoryURL)
        switch classification.safetyClass {
        case .safe, .unknown:
            return true
        case .unsafe:
            return false
        }
    }
}
