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

    package let maxWaitSeconds: TimeInterval
    package let staleLockAgeSeconds: TimeInterval
    package let initialBackoffSeconds: TimeInterval
    package let maxBackoffSeconds: TimeInterval

    package init(
        maxWaitSeconds: TimeInterval = 30,
        staleLockAgeSeconds: TimeInterval = 30,
        initialBackoffSeconds: TimeInterval = 0.05,
        maxBackoffSeconds: TimeInterval = 0.5
    ) {
        self.maxWaitSeconds = maxWaitSeconds
        self.staleLockAgeSeconds = staleLockAgeSeconds
        self.initialBackoffSeconds = initialBackoffSeconds
        self.maxBackoffSeconds = maxBackoffSeconds
    }
}

package struct ValidationCoordinatorRuntime: Sendable {
    package static let live = Self(
        monotonicNow: validationNow,
        currentDate: Date.init,
        sleep: validationSleep,
        currentProcessID: { getpid() },
        processExists: validationProcessExists,
        beforeStaleLockRemoval: { _ in }
    )

    package let monotonicNow: @Sendable () -> TimeInterval
    package let currentDate: @Sendable () -> Date
    package let sleep: @Sendable (TimeInterval) async -> Void
    package let currentProcessID: @Sendable () -> Int32
    package let processExists: @Sendable (Int32) -> Bool
    package let beforeStaleLockRemoval: @Sendable (URL) -> Void

    package init(
        monotonicNow: @escaping @Sendable () -> TimeInterval,
        currentDate: @escaping @Sendable () -> Date,
        sleep: @escaping @Sendable (TimeInterval) async -> Void,
        currentProcessID: @escaping @Sendable () -> Int32,
        processExists: @escaping @Sendable (Int32) -> Bool,
        beforeStaleLockRemoval: @escaping @Sendable (URL) -> Void = { _ in }
    ) {
        self.monotonicNow = monotonicNow
        self.currentDate = currentDate
        self.sleep = sleep
        self.currentProcessID = currentProcessID
        self.processExists = processExists
        self.beforeStaleLockRemoval = beforeStaleLockRemoval
    }
}

package struct ValidationCoordinatorLockMetadata: Codable, Equatable, Sendable {
    package let pid: Int32
    package let createdAt: TimeInterval
}

package let sharedRunCacheVersion = 2

package func sharedRunCacheKey(for signature: String) -> String {
    "shared-run-v\(sharedRunCacheVersion)-\(signature)"
}

package func validationSleep(_ interval: TimeInterval) async {
    guard interval > 0 else {
        return
    }

    let nanoseconds = UInt64((interval * 1_000_000_000).rounded(.up))
    try? await Task.sleep(nanoseconds: nanoseconds)
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
        outputDirectoryPath: String
    ) async throws -> ValidationExecutionOutcome {
        try await coordinate(
            rootPath: rootPath,
            toolPath: toolPath,
            stateDirectoryPath: stateDirectoryPath,
            outputDirectoryPath: outputDirectoryPath,
            runner: LiveValidationCommandRunner()
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
                createdAt: runtime.currentDate().timeIntervalSince1970
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
            await runtime.sleep(delaySeconds)
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
            stderr: "Timed out waiting for validation coordinator lock at '\(lockURL.path(percentEncoded: false))' after \(formatSeconds(lockPolicy.maxWaitSeconds))s.\n"
        )
        return try finalizeOutcome(
            result: timeoutResult,
            wasCached: false,
            sharedRunRecord: timeoutRecord
        )
    }
}

private func loadCachedSharedRun(
    resultURL: URL,
    sharedRunRecordURL: URL
) -> (result: ValidationCommandResult, record: SharedValidationRunRecord)? {
    guard
        let result = loadCachedResult(at: resultURL),
        let record = loadSharedRunRecord(at: sharedRunRecordURL)
    else {
        return nil
    }

    return (result, record)
}

private func loadCachedResult(at url: URL) -> ValidationCommandResult? {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return nil
    }

    guard
        let data = try? Data(contentsOf: url),
        let result = try? JSONDecoder().decode(ValidationCommandResult.self, from: data)
    else {
        return nil
    }

    return result
}

private func persistResult(_ result: ValidationCommandResult, to url: URL) throws {
    let data = try JSONEncoder().encode(result)
    try data.write(to: url, options: .atomic)
}

private func writeStamp(signature: String, result: ValidationCommandResult, to outputDirectoryURL: URL) throws {
    let stampURL = outputDirectoryURL.appendingPathComponent("dag-validation-stamp.txt")
    let content = "signature=\(signature)\nexitCode=\(result.exitCode)\n"
    try content.write(to: stampURL, atomically: true, encoding: .utf8)
}

private func persistMetricsArtifact(_ artifact: ValidationMetricsArtifact, to url: URL) throws {
    let data = try JSONEncoder().encode(artifact)
    try data.write(to: url, options: .atomic)
}

private func loadSharedRunRecord(at url: URL) -> SharedValidationRunRecord? {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return nil
    }

    guard
        let data = try? Data(contentsOf: url),
        let record = try? JSONDecoder().decode(SharedValidationRunRecord.self, from: data)
    else {
        return nil
    }

    return record
}

private func persistSharedRunRecord(_ record: SharedValidationRunRecord, to url: URL) throws {
    let data = try JSONEncoder().encode(record)
    try data.write(to: url, options: .atomic)
}

private func persistSummaryReport(_ content: String, to url: URL) throws {
    try content.write(to: url, atomically: true, encoding: .utf8)
}

private func acquireLock(at url: URL) throws -> Int32? {
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

private func persistLockMetadata(
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

private func loadLockMetadata(at url: URL) -> ValidationCoordinatorLockMetadata? {
    guard
        let data = try? Data(contentsOf: url),
        let metadata = try? JSONDecoder().decode(ValidationCoordinatorLockMetadata.self, from: data),
        metadata.pid > 0
    else {
        return nil
    }

    return metadata
}

private func releaseLock(descriptor: Int32, at url: URL) {
    close(descriptor)
    try? FileManager.default.removeItem(at: url)
}

private func pruneSharedRunDirectories(keepingDirectoryName directoryName: String, in stateDirectoryURL: URL) throws {
    let fileManager = FileManager.default
    let entries = try fileManager.contentsOfDirectory(
        at: stateDirectoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )

    for entry in entries {
        let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true, entry.lastPathComponent != directoryName else {
            continue
        }
        try? fileManager.removeItem(at: entry)
    }
}

private func recoverStaleLockIfNeeded(
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

private func lockFileAgeSeconds(at path: String, now: Date) -> TimeInterval? {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
        return nil
    }

    let referenceDate = (attributes[.modificationDate] as? Date) ?? (attributes[.creationDate] as? Date)
    guard let referenceDate else {
        return nil
    }

    return max(0, now.timeIntervalSince(referenceDate))
}

private struct POSIXLockError: LocalizedError {
    let code: Int32
    let path: String

    var errorDescription: String? {
        "Failed to acquire validation lock at '\(path)' (errno: \(code))."
    }
}

private struct ValidationCoordinatorIOError: LocalizedError {
    let path: String
    let operation: String
    let underlying: Error

    var errorDescription: String? {
        "Failed to \(operation) at '\(path)': \(underlying.localizedDescription)"
    }
}

private final class LockedDataBuffer: @unchecked Sendable {
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

private func validationProcessExists(_ pid: Int32) -> Bool {
    guard pid > 0 else {
        return false
    }

    let result = kill(pid, 0)
    if result == 0 {
        return true
    }

    return errno == EPERM
}

private func formatSeconds(_ value: TimeInterval) -> String {
    String(format: "%.2f", value)
}

private func installReadHandler(on handle: FileHandle, buffer: LockedDataBuffer) {
    handle.readabilityHandler = { readableHandle in
        let chunk = readableHandle.availableData
        if chunk.isEmpty {
            readableHandle.readabilityHandler = nil
            return
        }

        buffer.append(chunk)
    }
}
