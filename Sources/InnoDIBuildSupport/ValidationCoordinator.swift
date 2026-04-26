import Foundation

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
    func runValidationTool(toolPath: String, rootPath: String) throws -> ValidationCommandResult
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
        /// `O_CREAT | O_EXCL` is not atomic (NFSv3, SMB/CIFS, some FUSE).
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
    /// floating-point number of seconds. Unparseable or non-positive values
    /// fall back to the default and invoke `warningHandler` with a message
    /// explaining the fallback (default implementation writes to stderr) so
    /// the misconfiguration surfaces at the first build.
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
        guard let parsed = Double(raw), parsed > 0 else {
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
    package let beforeStaleLockRemoval: @Sendable (URL) -> Void

    package init(
        monotonicNow: @escaping @Sendable () -> TimeInterval,
        currentDate: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        currentProcessID: @escaping @Sendable () -> Int32,
        processExists: @escaping @Sendable (Int32) -> Bool,
        currentBootID: @escaping @Sendable () -> Int64? = BootIDProvider.live,
        beforeStaleLockRemoval: @escaping @Sendable (URL) -> Void = { _ in }
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

package let sharedRunCacheVersion = 2

package func sharedRunCacheKey(for signature: String) -> String {
    "shared-run-v\(sharedRunCacheVersion)-\(signature)"
}

package func validationSleep(_ interval: TimeInterval) async throws {
    guard interval > 0 else {
        return
    }

    let nanoseconds = UInt64((interval * 1_000_000_000).rounded(.up))
    try await Task.sleep(nanoseconds: nanoseconds)
}

/// Default process runner used by the coordinator to execute the DAG validator.
package struct LiveValidationCommandRunner: ValidationCommandRunning {
    package init() {}

    package func runValidationTool(toolPath: String, rootPath: String) throws -> ValidationCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = ["--root", rootPath, "--validate-dag"]
        process.currentDirectoryURL = URL(fileURLWithPath: rootPath)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = LockedDataBuffer()
        let stderrBuffer = LockedDataBuffer()
        installReadHandler(on: stdoutPipe.fileHandleForReading, buffer: stdoutBuffer)
        installReadHandler(on: stderrPipe.fileHandleForReading, buffer: stderrBuffer)

        try process.run()
        process.waitUntilExit()

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        stdoutHandle.readabilityHandler = nil
        stderrHandle.readabilityHandler = nil
        stdoutBuffer.append(stdoutHandle.readDataToEndOfFile())
        stderrBuffer.append(stderrHandle.readDataToEndOfFile())

        let stdout = String(data: stdoutBuffer.data, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBuffer.data, encoding: .utf8) ?? ""

        return ValidationCommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
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
        toolPath: String,
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

    package static func coordinate<Runner: ValidationCommandRunning>(
        rootPath: String,
        toolPath: String,
        stateDirectoryPath: String,
        outputDirectoryPath: String,
        runner: Runner,
        verboseLoggingEnabled: Bool = ValidationLogging.isVerboseEnabled(),
        lockPolicy: ValidationCoordinatorLockPolicy = .default,
        runtime: ValidationCoordinatorRuntime = .live
    ) async throws -> ValidationExecutionOutcome {
        let coordinatorStartTime = validationNow()
        let fileManager = FileManager.default
        let stateDirectoryURL = URL(fileURLWithPath: stateDirectoryPath, isDirectory: true)
        let outputDirectoryURL = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)

        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        let signatureCollectionStartTime = validationNow()
        let signatureCollection = try collectValidationSignatureWithMetrics(
            rootPath: rootPath,
            stateDirectoryPath: stateDirectoryPath
        )
        let signature = signatureCollection.signature
        let sharedRunKey = sharedRunCacheKey(for: signature)
        let signatureCollectionMilliseconds = validationElapsedMilliseconds(since: signatureCollectionStartTime)
        let sharedRunDirectory = stateDirectoryURL.appendingPathComponent(sharedRunKey, isDirectory: true)
        try fileManager.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)
        try pruneSharedRunDirectories(keepingDirectoryName: sharedRunKey, in: stateDirectoryURL)

        let resultURL = sharedRunDirectory.appendingPathComponent("result.json")
        let sharedRunRecordURL = sharedRunDirectory.appendingPathComponent("validation-metrics.json")
        let sharedSummaryURL = sharedRunDirectory.appendingPathComponent("validation-summary.md")
        let lockURL = sharedRunDirectory.appendingPathComponent("lock")

        // Filesystem safety guard. Refuse to acquire the cross-process
        // lock on filesystems where `O_CREAT | O_EXCL` is not atomic,
        // unless the operator opted in via INNODI_ALLOW_UNSAFE_LOCK=1.
        // See `Sources/InnoDI/InnoDI.docc/lock-safety.md`.
        if let unsafeFailure = checkLockFilesystemSafety(
            lockDirectory: sharedRunDirectory,
            allowUnsafe: lockPolicy.allowUnsafeFilesystem
        ) {
            return try finalizeOutcome(
                result: unsafeFailure.result,
                wasCached: false,
                sharedRunRecord: unsafeFailure.record
            )
        }

        func finalizeOutcome(
            result: ValidationCommandResult,
            wasCached: Bool,
            sharedRunRecord: SharedValidationRunRecord
        ) throws -> ValidationExecutionOutcome {
            try writeStamp(signature: signature, result: result, to: outputDirectoryURL)
            let combinedReasonCodes = Array(
                Set(signatureCollection.reasonCodes + sharedRunRecord.reasonCodes)
            )
            .sorted { $0.rawValue < $1.rawValue }

            let artifact = ValidationMetricsArtifact(
                signature: signature,
                wasCached: wasCached,
                resultExitCode: result.exitCode,
                reasonCodes: combinedReasonCodes,
                signatureMetrics: signatureCollection.metrics,
                fileChanges: signatureCollection.fileChanges,
                invocationMetrics: ValidationInvocationMetrics(
                    signatureCollectionMilliseconds: signatureCollectionMilliseconds,
                    totalCoordinatorMilliseconds: validationElapsedMilliseconds(since: coordinatorStartTime)
                ),
                liveRunMetrics: sharedRunRecord.liveRunMetrics,
                issues: sharedRunRecord.issues,
                humanSummarySource: "dag-validation-summary.md"
            )
            try persistMetricsArtifact(
                artifact,
                to: outputDirectoryURL.appendingPathComponent("dag-validation-metrics.json")
            )
            try persistSummaryReport(
                ValidationLogging.renderMarkdownSummary(for: artifact),
                to: outputDirectoryURL.appendingPathComponent("dag-validation-summary.md")
            )

            let verboseSummary = verboseLoggingEnabled ? ValidationLogging.renderSummary(for: artifact) : nil
            return ValidationExecutionOutcome(
                result: result,
                wasCached: wasCached,
                signature: signature,
                metricsArtifact: artifact,
                verboseSummary: verboseSummary
            )
        }

        if let (cachedResult, sharedRunRecord) = loadCachedSharedRun(
            resultURL: resultURL,
            sharedRunRecordURL: sharedRunRecordURL
        ) {
            return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
        }

        func executeLockedValidation(
            descriptor lockDescriptor: Int32,
            recoveredStaleLock: Bool
        ) throws -> ValidationExecutionOutcome {
            let lockMetadata = ValidationCoordinatorLockMetadata(
                pid: runtime.currentProcessID(),
                createdAt: runtime.currentDate().timeIntervalSince1970,
                bootID: runtime.currentBootID()
            )

            do {
                try persistLockMetadata(lockMetadata, descriptor: lockDescriptor, path: lockURL.path(percentEncoded: false))
            } catch {
                releaseLock(descriptor: lockDescriptor, at: lockURL)
                throw error
            }
            defer { releaseLock(descriptor: lockDescriptor, at: lockURL) }

            if let (cachedResult, sharedRunRecord) = loadCachedSharedRun(
                resultURL: resultURL,
                sharedRunRecordURL: sharedRunRecordURL
            ) {
                return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
            }

            let result: ValidationCommandResult
            let customInitStartTime = validationNow()
            let customInitValidation = try CustomInitBuildValidator.validate(rootPath: rootPath)
            let customInitFailure = customInitValidation.asCommandResult()
            let customInitValidationMilliseconds = validationElapsedMilliseconds(since: customInitStartTime)

            let semanticValidationMilliseconds: Double
            let hierarchyValidationMilliseconds: Double
            let dagValidationMilliseconds: Double
            var liveRunReasonCodes: [ValidationReasonCode] = recoveredStaleLock
                ? [.staleLockRecovered]
                : []
            let issues: [ValidationIssue]
            if let customInitFailure {
                result = customInitFailure
                semanticValidationMilliseconds = 0
                hierarchyValidationMilliseconds = 0
                dagValidationMilliseconds = 0
                liveRunReasonCodes.append(.liveRunCustomInitFailure)
                issues = customInitValidation.issues
            } else {
                let semanticValidationStartTime = validationNow()
                let semanticValidation = try ContainerSemanticBuildValidator.validate(rootPath: rootPath)
                let semanticFailure = semanticValidation.asCommandResult()
                semanticValidationMilliseconds = validationElapsedMilliseconds(since: semanticValidationStartTime)

                if let semanticFailure {
                    result = semanticFailure
                    hierarchyValidationMilliseconds = 0
                    dagValidationMilliseconds = 0
                    liveRunReasonCodes.append(.liveRunSemanticFailure)
                    issues = semanticValidation.issues
                } else {
                    let hierarchyValidationStartTime = validationNow()
                    let hierarchyValidation = try WorkspaceHierarchyBuildValidator.validate(rootPath: rootPath)
                    let hierarchyFailure = hierarchyValidation.asCommandResult()
                    hierarchyValidationMilliseconds = validationElapsedMilliseconds(since: hierarchyValidationStartTime)

                    if let hierarchyFailure {
                        result = hierarchyFailure
                        dagValidationMilliseconds = 0
                        liveRunReasonCodes.append(.liveRunSemanticValidation)
                        liveRunReasonCodes.append(.liveRunHierarchyFailure)
                        issues = semanticValidation.issues + hierarchyValidation.issues
                    } else {
                        let dagValidationStartTime = validationNow()
                        result = try runner.runValidationTool(toolPath: toolPath, rootPath: rootPath)
                        dagValidationMilliseconds = validationElapsedMilliseconds(since: dagValidationStartTime)
                        liveRunReasonCodes.append(.liveRunSemanticValidation)
                        liveRunReasonCodes.append(.liveRunHierarchyValidation)
                        liveRunReasonCodes.append(.liveRunDAGValidation)
                        issues = semanticValidation.issues + hierarchyValidation.issues
                    }
                }
            }

            let sharedRunRecord = SharedValidationRunRecord(
                liveRunMetrics: ValidationLiveRunMetrics(
                    customInitValidationMilliseconds: customInitValidationMilliseconds,
                    semanticValidationMilliseconds: semanticValidationMilliseconds,
                    hierarchyValidationMilliseconds: hierarchyValidationMilliseconds,
                    dagValidationMilliseconds: dagValidationMilliseconds
                ),
                reasonCodes: liveRunReasonCodes,
                issues: issues
            )
            try persistSharedRunRecord(sharedRunRecord, to: sharedRunRecordURL)
            try persistResult(result, to: resultURL)
            let sharedArtifact = ValidationMetricsArtifact(
                signature: signature,
                wasCached: false,
                resultExitCode: result.exitCode,
                reasonCodes: Array(Set(signatureCollection.reasonCodes + liveRunReasonCodes)).sorted { $0.rawValue < $1.rawValue },
                signatureMetrics: signatureCollection.metrics,
                fileChanges: signatureCollection.fileChanges,
                invocationMetrics: ValidationInvocationMetrics(
                    signatureCollectionMilliseconds: signatureCollectionMilliseconds,
                    totalCoordinatorMilliseconds: validationElapsedMilliseconds(since: coordinatorStartTime)
                ),
                liveRunMetrics: sharedRunRecord.liveRunMetrics,
                issues: issues,
                humanSummarySource: "validation-summary.md"
            )
            try persistSummaryReport(
                ValidationLogging.renderMarkdownSummary(for: sharedArtifact),
                to: sharedSummaryURL
            )

            return try finalizeOutcome(result: result, wasCached: false, sharedRunRecord: sharedRunRecord)
        }

        func acquireAndExecuteLiveValidation(recoveredStaleLock: Bool) throws -> ValidationExecutionOutcome? {
            guard let lockDescriptor = try acquireLock(at: lockURL) else {
                return nil
            }

            return try executeLockedValidation(
                descriptor: lockDescriptor,
                recoveredStaleLock: recoveredStaleLock
            )
        }

        let lockAcquisitionDeadline = runtime.monotonicNow() + lockPolicy.maxWaitSeconds
        var backoffSeconds = lockPolicy.initialBackoffSeconds
        var recoveredStaleLock = false

        while runtime.monotonicNow() < lockAcquisitionDeadline {
            if let outcome = try acquireAndExecuteLiveValidation(recoveredStaleLock: recoveredStaleLock) {
                return outcome
            }

            if try recoverStaleLockIfNeeded(
                at: lockURL,
                staleLockAgeSeconds: lockPolicy.staleLockAgeSeconds,
                runtime: runtime
            ) {
                recoveredStaleLock = true
                backoffSeconds = lockPolicy.initialBackoffSeconds
                continue
            }

            if let (cachedResult, sharedRunRecord) = loadCachedSharedRun(
                resultURL: resultURL,
                sharedRunRecordURL: sharedRunRecordURL
            ) {
                return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
            }

            let remainingWait = lockAcquisitionDeadline - runtime.monotonicNow()
            guard remainingWait > 0 else {
                break
            }

            let delaySeconds = min(backoffSeconds, remainingWait)
            try await runtime.sleep(delaySeconds)
            backoffSeconds = min(backoffSeconds * 2, lockPolicy.maxBackoffSeconds)
        }

        if let (cachedResult, sharedRunRecord) = loadCachedSharedRun(
            resultURL: resultURL,
            sharedRunRecordURL: sharedRunRecordURL
        ) {
            return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
        }

        if try recoverStaleLockIfNeeded(
            at: lockURL,
            staleLockAgeSeconds: lockPolicy.staleLockAgeSeconds,
            runtime: runtime
        ) {
            recoveredStaleLock = true
        }

        if let (cachedResult, sharedRunRecord) = loadCachedSharedRun(
            resultURL: resultURL,
            sharedRunRecordURL: sharedRunRecordURL
        ) {
            return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
        }

        if let outcome = try acquireAndExecuteLiveValidation(recoveredStaleLock: recoveredStaleLock) {
            return outcome
        }

        let timeoutReasonCodes: [ValidationReasonCode] = recoveredStaleLock
            ? [.staleLockRecovered, .lockContentionTimeout]
            : [.lockContentionTimeout]
        let timeoutRecord = SharedValidationRunRecord(
            liveRunMetrics: ValidationLiveRunMetrics(
                customInitValidationMilliseconds: 0,
                semanticValidationMilliseconds: 0,
                hierarchyValidationMilliseconds: 0,
                dagValidationMilliseconds: 0
            ),
            reasonCodes: timeoutReasonCodes,
            issues: []
        )
        let timeoutResult = ValidationCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: lockTimeoutDiagnosticMessage(
                lockURL: lockURL,
                lockPolicy: lockPolicy,
                recoveredStaleLock: recoveredStaleLock,
                runtime: runtime
            )
        )
        return try finalizeOutcome(
            result: timeoutResult,
            wasCached: false,
            sharedRunRecord: timeoutRecord
        )
    }
}
