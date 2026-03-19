import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

package struct ValidationExecutionOutcome: Equatable, Sendable {
    package let result: ValidationCommandResult
    package let wasCached: Bool
    package let signature: String
    package let metricsArtifact: ValidationMetricsArtifact
    package let verboseSummary: String?
}

package protocol ValidationCommandRunning: Sendable {
    func runValidationTool(toolPath: String, rootPath: String) throws -> ValidationCommandResult
}

package struct SharedValidationRunRecord: Codable, Equatable, Sendable {
    package let liveRunMetrics: ValidationLiveRunMetrics
    package let reasonCodes: [ValidationReasonCode]
    package let issues: [ValidationIssue]
}

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

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        return ValidationCommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout,
            stderr: stderr
        )
    }
}

package enum ValidationCoordinator {
    package static func coordinate(
        rootPath: String,
        toolPath: String,
        stateDirectoryPath: String,
        outputDirectoryPath: String
    ) throws -> ValidationExecutionOutcome {
        try coordinate(
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
        verboseLoggingEnabled: Bool = ValidationLogging.isVerboseEnabled()
    ) throws -> ValidationExecutionOutcome {
        let coordinatorStartTime = CFAbsoluteTimeGetCurrent()
        let fileManager = FileManager.default
        let stateDirectoryURL = URL(fileURLWithPath: stateDirectoryPath, isDirectory: true)
        let outputDirectoryURL = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)

        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        let signatureCollectionStartTime = CFAbsoluteTimeGetCurrent()
        let signatureCollection = try collectValidationSignatureWithMetrics(
            rootPath: rootPath,
            stateDirectoryPath: stateDirectoryPath
        )
        let signature = signatureCollection.signature
        let signatureCollectionMilliseconds = validationElapsedMilliseconds(since: signatureCollectionStartTime)
        let sharedRunDirectory = stateDirectoryURL.appendingPathComponent(signature, isDirectory: true)
        try fileManager.createDirectory(at: sharedRunDirectory, withIntermediateDirectories: true)
        try pruneSharedRunDirectories(keepingSignature: signature, in: stateDirectoryURL)

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

        if let cachedResult = try loadCachedResult(at: resultURL) {
            let sharedRunRecord = try loadSharedRunRecord(at: sharedRunRecordURL)
            return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
        }

        while true {
            if let lockDescriptor = try acquireLock(at: lockURL) {
                defer { releaseLock(descriptor: lockDescriptor, at: lockURL) }

                if let cachedResult = try loadCachedResult(at: resultURL) {
                    let sharedRunRecord = try loadSharedRunRecord(at: sharedRunRecordURL)
                    return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
                }

                let result: ValidationCommandResult
                let customInitStartTime = CFAbsoluteTimeGetCurrent()
                let customInitValidation = try CustomInitBuildValidator.validate(rootPath: rootPath)
                let customInitFailure = customInitValidation.asCommandResult()
                let customInitValidationMilliseconds = validationElapsedMilliseconds(since: customInitStartTime)

                let dagValidationMilliseconds: Double
                let liveRunReasonCodes: [ValidationReasonCode]
                let issues: [ValidationIssue]
                if let customInitFailure {
                    result = customInitFailure
                    dagValidationMilliseconds = 0
                    liveRunReasonCodes = [.liveRunCustomInitFailure]
                    issues = customInitValidation.issues
                } else {
                    let dagValidationStartTime = CFAbsoluteTimeGetCurrent()
                    result = try runner.runValidationTool(toolPath: toolPath, rootPath: rootPath)
                    dagValidationMilliseconds = validationElapsedMilliseconds(since: dagValidationStartTime)
                    liveRunReasonCodes = [.liveRunDAGValidation]
                    issues = []
                }

                let sharedRunRecord = SharedValidationRunRecord(
                    liveRunMetrics: ValidationLiveRunMetrics(
                        customInitValidationMilliseconds: customInitValidationMilliseconds,
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

            if let cachedResult = try waitForCachedResult(resultURL: resultURL, lockURL: lockURL) {
                let sharedRunRecord = try loadSharedRunRecord(at: sharedRunRecordURL)
                return try finalizeOutcome(result: cachedResult, wasCached: true, sharedRunRecord: sharedRunRecord)
            }
        }
    }
}

private func loadCachedResult(at url: URL) throws -> ValidationCommandResult? {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return nil
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ValidationCommandResult.self, from: data)
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

private func loadSharedRunRecord(at url: URL) throws -> SharedValidationRunRecord {
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
        return SharedValidationRunRecord(
            liveRunMetrics: ValidationLiveRunMetrics(
                customInitValidationMilliseconds: 0,
                dagValidationMilliseconds: 0
            ),
            reasonCodes: [],
            issues: []
        )
    }

    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(SharedValidationRunRecord.self, from: data)
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

private func releaseLock(descriptor: Int32, at url: URL) {
    close(descriptor)
    try? FileManager.default.removeItem(at: url)
}

private func pruneSharedRunDirectories(keepingSignature signature: String, in stateDirectoryURL: URL) throws {
    let fileManager = FileManager.default
    let entries = try fileManager.contentsOfDirectory(
        at: stateDirectoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )

    for entry in entries {
        let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true, entry.lastPathComponent != signature else {
            continue
        }
        try? fileManager.removeItem(at: entry)
    }
}

private func waitForCachedResult(resultURL: URL, lockURL: URL) throws -> ValidationCommandResult? {
    let timeoutDate = Date().addingTimeInterval(30)

    while Date() < timeoutDate {
        if let cachedResult = try loadCachedResult(at: resultURL) {
            return cachedResult
        }

        if !FileManager.default.fileExists(atPath: lockURL.path(percentEncoded: false)) {
            return nil
        }

        Thread.sleep(forTimeInterval: 0.05)
    }

    return nil
}

private struct POSIXLockError: LocalizedError {
    let code: Int32
    let path: String

    var errorDescription: String? {
        "Failed to acquire validation lock at '\(path)' (errno: \(code))."
    }
}
