//
//  ValidationCoordinator+Execution.swift
//  InnoDIBuildSupport
//
//  Concern-focused execution stages for a prepared validation signature.
//  The entry-point coordinator prepares inputs; these types own artifact
//  writing, the locked validator pipeline, and lock-contention resolution.
//

import Foundation
import InnoDIWorkspaceAnalysis

struct ValidationSharedRunPaths {
    let directory: URL
    let result: URL
    let record: URL
    let summary: URL
    let lock: URL

    init(stateDirectory: URL, sharedRunKey: String) {
        let directory = stateDirectory.appendingPathComponent(
            sharedRunKey,
            isDirectory: true
        )
        self.directory = directory
        result = directory.appendingPathComponent("result.json")
        record = directory.appendingPathComponent("validation-metrics.json")
        summary = directory.appendingPathComponent("validation-summary.md")
        lock = directory.appendingPathComponent("lock")
    }

    func loadCachedRun() -> (
        result: ValidationCommandResult,
        record: SharedValidationRunRecord
    )? {
        loadCachedSharedRun(resultURL: result, sharedRunRecordURL: record)
    }
}

struct ValidationOutcomeWriter {
    let signatureCollection: ValidationSignatureCollectionResult
    let signatureCollectionMilliseconds: Double
    let coordinatorStartTime: TimeInterval
    let outputDirectory: URL
    let verboseLoggingEnabled: Bool

    var signature: String {
        signatureCollection.signature
    }

    func finalize(
        result: ValidationCommandResult,
        wasCached: Bool,
        sharedRunRecord: SharedValidationRunRecord
    ) throws -> ValidationExecutionOutcome {
        try writeStamp(
            signature: signature,
            result: result,
            to: outputDirectory
        )
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
                totalCoordinatorMilliseconds: validationElapsedMilliseconds(
                    since: coordinatorStartTime
                )
            ),
            liveRunMetrics: sharedRunRecord.liveRunMetrics,
            issues: sharedRunRecord.issues,
            humanSummarySource: "dag-validation-summary.md"
        )
        try persistMetricsArtifact(
            artifact,
            to: outputDirectory.appendingPathComponent(
                "dag-validation-metrics.json"
            )
        )
        try persistSummaryReport(
            ValidationLogging.renderMarkdownSummary(for: artifact),
            to: outputDirectory.appendingPathComponent(
                "dag-validation-summary.md"
            )
        )

        let verboseSummary = verboseLoggingEnabled
            ? ValidationLogging.renderSummary(for: artifact)
            : nil
        return ValidationExecutionOutcome(
            result: result,
            wasCached: wasCached,
            signature: signature,
            metricsArtifact: artifact,
            verboseSummary: verboseSummary
        )
    }
}

struct ValidationLockedRunExecutor<Runner: ValidationCommandRunning> {
    let rootPath: String
    let analysisManifest: ValidatedWorkspaceAnalysisManifest?
    let toolPath: String?
    let runner: Runner
    let runtime: ValidationCoordinatorRuntime
    let signatureCollectionOutput: ValidationSignatureCollectionOutput
    let paths: ValidationSharedRunPaths
    let outcomeWriter: ValidationOutcomeWriter

    func acquireAndExecute(
        recoveredStaleLock: Bool
    ) throws -> ValidationExecutionOutcome? {
        guard let lockDescriptor = try acquireLock(at: paths.lock) else {
            return nil
        }
        return try execute(
            lockDescriptor: lockDescriptor,
            recoveredStaleLock: recoveredStaleLock
        )
    }

    private func execute(
        lockDescriptor: Int32,
        recoveredStaleLock: Bool
    ) throws -> ValidationExecutionOutcome {
        let lockMetadata = ValidationCoordinatorLockMetadata(
            pid: runtime.currentProcessID(),
            createdAt: runtime.currentDate().timeIntervalSince1970,
            bootID: runtime.currentBootID()
        )

        do {
            try persistLockMetadata(
                lockMetadata,
                descriptor: lockDescriptor,
                path: paths.lock.path(percentEncoded: false)
            )
        } catch {
            releaseLock(descriptor: lockDescriptor, at: paths.lock)
            throw error
        }
        defer {
            releaseLock(descriptor: lockDescriptor, at: paths.lock)
        }

        if let cachedRun = paths.loadCachedRun() {
            return try outcomeWriter.finalize(
                result: cachedRun.result,
                wasCached: true,
                sharedRunRecord: cachedRun.record
            )
        }

        let liveRun = try executeValidationPipeline(
            recoveredStaleLock: recoveredStaleLock
        )
        try persistSharedRunRecord(liveRun.record, to: paths.record)
        try persistResult(liveRun.result, to: paths.result)
        try persistSharedSummary(
            result: liveRun.result,
            record: liveRun.record
        )

        return try outcomeWriter.finalize(
            result: liveRun.result,
            wasCached: false,
            sharedRunRecord: liveRun.record
        )
    }

    private func executeValidationPipeline(
        recoveredStaleLock: Bool
    ) throws -> (
        result: ValidationCommandResult,
        record: SharedValidationRunRecord
    ) {
        let customInitStartTime = validationNow()
        let workspaceSnapshot: WorkspaceSourceSnapshot
        if let analysisManifest {
            workspaceSnapshot = try loadWorkspaceSourceSnapshot(
                validated: analysisManifest,
                reusingParsedSources: signatureCollectionOutput.parsedSources
            )
        } else {
            workspaceSnapshot = try loadWorkspaceSourceSnapshot(
                rootPath: rootPath,
                reusingParsedSources: signatureCollectionOutput.parsedSources
            )
        }

        let aliasReport = DeferredWrapperAliasBuildValidator.validate(
            snapshot: workspaceSnapshot
        )
        let customInitValidation = try CustomInitBuildValidator.validate(
            snapshot: workspaceSnapshot
        )
        let customInitFailure = customInitValidation.asCommandResult()
        let customInitValidationMilliseconds = validationElapsedMilliseconds(
            since: customInitStartTime
        )

        let pipelineResult = try executePostCustomInitStages(
            workspaceSnapshot: workspaceSnapshot,
            customInitValidation: customInitValidation,
            customInitFailure: customInitFailure,
            recoveredStaleLock: recoveredStaleLock
        )
        let record = SharedValidationRunRecord(
            liveRunMetrics: ValidationLiveRunMetrics(
                customInitValidationMilliseconds: customInitValidationMilliseconds,
                semanticValidationMilliseconds: pipelineResult.semanticMilliseconds,
                hierarchyValidationMilliseconds: pipelineResult.hierarchyMilliseconds,
                dagValidationMilliseconds: pipelineResult.dagMilliseconds
            ),
            reasonCodes: pipelineResult.reasonCodes,
            issues: pipelineResult.issues + aliasReport.issues
        )
        return (pipelineResult.result, record)
    }

    private func executePostCustomInitStages(
        workspaceSnapshot: WorkspaceSourceSnapshot,
        customInitValidation: ValidationIssueReport,
        customInitFailure: ValidationCommandResult?,
        recoveredStaleLock: Bool
    ) throws -> ValidationPipelineResult {
        var reasonCodes: [ValidationReasonCode] = recoveredStaleLock
            ? [.staleLockRecovered]
            : []
        if let customInitFailure {
            reasonCodes.append(.liveRunCustomInitFailure)
            return ValidationPipelineResult(
                result: customInitFailure,
                reasonCodes: reasonCodes,
                issues: customInitValidation.issues
            )
        }

        let semanticStartTime = validationNow()
        let qualifierValidation = GeneratedQualifierBuildValidator.validate(
            snapshot: workspaceSnapshot
        )
        let semanticValidation: ValidationIssueReport
        if qualifierValidation.hasFailures {
            semanticValidation = qualifierValidation
        } else {
            let containerValidation = try ContainerSemanticBuildValidator
                .validate(snapshot: workspaceSnapshot)
            semanticValidation = ValidationIssueReport(
                issues: qualifierValidation.issues + containerValidation.issues
            )
        }
        let semanticMilliseconds = validationElapsedMilliseconds(
            since: semanticStartTime
        )
        if let semanticFailure = semanticValidation.asCommandResult() {
            reasonCodes.append(.liveRunSemanticFailure)
            return ValidationPipelineResult(
                result: semanticFailure,
                reasonCodes: reasonCodes,
                issues: semanticValidation.issues,
                semanticMilliseconds: semanticMilliseconds
            )
        }

        let hierarchyStartTime = validationNow()
        let moduleGraph: WorkspaceModuleGraphSnapshot
        if let analysisManifest {
            moduleGraph = try ModuleGraphProvider.snapshot(
                validated: analysisManifest
            )
        } else {
            moduleGraph = try ModuleGraphProvider.snapshot(rootPath: rootPath)
        }
        let hierarchyValidation = try WorkspaceHierarchyBuildValidator.validate(
            snapshot: workspaceSnapshot,
            moduleGraph: moduleGraph
        )
        let hierarchyMilliseconds = validationElapsedMilliseconds(
            since: hierarchyStartTime
        )
        reasonCodes.append(.liveRunSemanticValidation)
        if let hierarchyFailure = hierarchyValidation.asCommandResult() {
            reasonCodes.append(.liveRunHierarchyFailure)
            return ValidationPipelineResult(
                result: hierarchyFailure,
                reasonCodes: reasonCodes,
                issues: semanticValidation.issues + hierarchyValidation.issues,
                semanticMilliseconds: semanticMilliseconds,
                hierarchyMilliseconds: hierarchyMilliseconds
            )
        }

        let dagStartTime = validationNow()
        let result = try runner.runValidationTool(
            toolPath: toolPath,
            rootPath: rootPath,
            snapshot: workspaceSnapshot
        )
        let dagMilliseconds = validationElapsedMilliseconds(since: dagStartTime)
        reasonCodes.append(.liveRunHierarchyValidation)
        reasonCodes.append(.liveRunDAGValidation)
        return ValidationPipelineResult(
            result: result,
            reasonCodes: reasonCodes,
            issues: semanticValidation.issues + hierarchyValidation.issues,
            semanticMilliseconds: semanticMilliseconds,
            hierarchyMilliseconds: hierarchyMilliseconds,
            dagMilliseconds: dagMilliseconds
        )
    }

    private func persistSharedSummary(
        result: ValidationCommandResult,
        record: SharedValidationRunRecord
    ) throws {
        let signatureCollection = signatureCollectionOutput.result
        let artifact = ValidationMetricsArtifact(
            signature: outcomeWriter.signature,
            wasCached: false,
            resultExitCode: result.exitCode,
            reasonCodes: Array(
                Set(signatureCollection.reasonCodes + record.reasonCodes)
            ).sorted { $0.rawValue < $1.rawValue },
            signatureMetrics: signatureCollection.metrics,
            fileChanges: signatureCollection.fileChanges,
            invocationMetrics: ValidationInvocationMetrics(
                signatureCollectionMilliseconds: outcomeWriter
                    .signatureCollectionMilliseconds,
                totalCoordinatorMilliseconds: validationElapsedMilliseconds(
                    since: outcomeWriter.coordinatorStartTime
                )
            ),
            liveRunMetrics: record.liveRunMetrics,
            issues: record.issues,
            humanSummarySource: "validation-summary.md"
        )
        try persistSummaryReport(
            ValidationLogging.renderMarkdownSummary(for: artifact),
            to: paths.summary
        )
    }
}

private struct ValidationPipelineResult {
    let result: ValidationCommandResult
    let reasonCodes: [ValidationReasonCode]
    let issues: [ValidationIssue]
    let semanticMilliseconds: Double
    let hierarchyMilliseconds: Double
    let dagMilliseconds: Double

    init(
        result: ValidationCommandResult,
        reasonCodes: [ValidationReasonCode],
        issues: [ValidationIssue],
        semanticMilliseconds: Double = 0,
        hierarchyMilliseconds: Double = 0,
        dagMilliseconds: Double = 0
    ) {
        self.result = result
        self.reasonCodes = reasonCodes
        self.issues = issues
        self.semanticMilliseconds = semanticMilliseconds
        self.hierarchyMilliseconds = hierarchyMilliseconds
        self.dagMilliseconds = dagMilliseconds
    }
}

struct ValidationSharedRunResolver<Runner: ValidationCommandRunning> {
    let executor: ValidationLockedRunExecutor<Runner>
    let outcomeWriter: ValidationOutcomeWriter
    let paths: ValidationSharedRunPaths
    let lockPolicy: ValidationCoordinatorLockPolicy
    let runtime: ValidationCoordinatorRuntime

    func resolve() async throws -> ValidationExecutionOutcome {
        let lockAcquisitionDeadline = runtime.monotonicNow()
            + lockPolicy.maxWaitSeconds
        var backoffSeconds = lockPolicy.initialBackoffSeconds
        var recoveredStaleLock = false

        while runtime.monotonicNow() < lockAcquisitionDeadline {
            if let outcome = try executor.acquireAndExecute(
                recoveredStaleLock: recoveredStaleLock
            ) {
                return outcome
            }

            if try await recoverStaleLockIfNeeded(
                at: paths.lock,
                staleLockAgeSeconds: lockPolicy.staleLockAgeSeconds,
                runtime: runtime
            ) {
                recoveredStaleLock = true
                backoffSeconds = lockPolicy.initialBackoffSeconds
                continue
            }

            if let cachedOutcome = try finalizeCachedRun() {
                return cachedOutcome
            }

            let remainingWait = lockAcquisitionDeadline
                - runtime.monotonicNow()
            guard remainingWait > 0 else {
                break
            }

            let delaySeconds = min(backoffSeconds, remainingWait)
            try await runtime.sleep(delaySeconds)
            backoffSeconds = min(
                backoffSeconds * 2,
                lockPolicy.maxBackoffSeconds
            )
        }

        if let cachedOutcome = try finalizeCachedRun() {
            return cachedOutcome
        }
        if try await recoverStaleLockIfNeeded(
            at: paths.lock,
            staleLockAgeSeconds: lockPolicy.staleLockAgeSeconds,
            runtime: runtime
        ) {
            recoveredStaleLock = true
        }
        if let cachedOutcome = try finalizeCachedRun() {
            return cachedOutcome
        }
        if let outcome = try executor.acquireAndExecute(
            recoveredStaleLock: recoveredStaleLock
        ) {
            return outcome
        }

        return try finalizeTimeout(recoveredStaleLock: recoveredStaleLock)
    }

    private func finalizeCachedRun() throws -> ValidationExecutionOutcome? {
        guard let cachedRun = paths.loadCachedRun() else {
            return nil
        }
        return try outcomeWriter.finalize(
            result: cachedRun.result,
            wasCached: true,
            sharedRunRecord: cachedRun.record
        )
    }

    private func finalizeTimeout(
        recoveredStaleLock: Bool
    ) throws -> ValidationExecutionOutcome {
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
                lockURL: paths.lock,
                lockPolicy: lockPolicy,
                recoveredStaleLock: recoveredStaleLock,
                runtime: runtime
            )
        )
        return try outcomeWriter.finalize(
            result: timeoutResult,
            wasCached: false,
            sharedRunRecord: timeoutRecord
        )
    }
}
