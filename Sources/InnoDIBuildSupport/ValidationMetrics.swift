import Foundation

package enum ValidationReasonCode: String, Codable, Equatable, Sendable {
    case cacheHitMetadata = "cache-hit-metadata"
    case cacheHitContentHash = "cache-hit-content-hash"
    case cacheMissContentChanged = "cache-miss-content-changed"
    case cacheMissNewFile = "cache-miss-new-file"
    case cacheMissDeletedFile = "cache-miss-deleted-file"
    case cacheMissManifestVersion = "cache-miss-manifest-version"
    case staleLockRecovered = "stale-lock-recovered"
    case lockContentionTimeout = "lock-contention-timeout"
    case liveRunCustomInitFailure = "live-run-custom-init-failure"
    case liveRunSemanticValidation = "live-run-semantic-validation"
    case liveRunSemanticFailure = "live-run-semantic-failure"
    case liveRunDAGValidation = "live-run-dag-validation"
}

package struct ValidationSignatureMetrics: Codable, Equatable, Sendable {
    package let scannedFileCount: Int
    package let metadataCacheHitCount: Int
    package let contentHashReuseCount: Int
    package let astReparseCount: Int

    package var cacheHitCount: Int {
        metadataCacheHitCount + contentHashReuseCount
    }

    package var cacheMissCount: Int {
        astReparseCount
    }
}

package struct ValidationFileChangeDetails: Codable, Equatable, Sendable {
    package let newFiles: [String]
    package let deletedFiles: [String]
    package let reparsedFiles: [String]
    package let contentHashReusedFiles: [String]
    package let fallbackMatchedReferences: [String]

    package init(
        newFiles: [String] = [],
        deletedFiles: [String] = [],
        reparsedFiles: [String] = [],
        contentHashReusedFiles: [String] = [],
        fallbackMatchedReferences: [String] = []
    ) {
        self.newFiles = newFiles
        self.deletedFiles = deletedFiles
        self.reparsedFiles = reparsedFiles
        self.contentHashReusedFiles = contentHashReusedFiles
        self.fallbackMatchedReferences = fallbackMatchedReferences
    }
}

package struct ValidationSignatureCollectionResult: Codable, Equatable, Sendable {
    package let signature: String
    package let metrics: ValidationSignatureMetrics
    package let reasonCodes: [ValidationReasonCode]
    package let fileChanges: ValidationFileChangeDetails
}

package struct ValidationInvocationMetrics: Codable, Equatable, Sendable {
    package let signatureCollectionMilliseconds: Double
    package let totalCoordinatorMilliseconds: Double
}

package struct ValidationLiveRunMetrics: Codable, Equatable, Sendable {
    package let customInitValidationMilliseconds: Double
    package let semanticValidationMilliseconds: Double
    package let dagValidationMilliseconds: Double
}

package struct ValidationMetricsArtifact: Codable, Equatable, Sendable {
    package static let currentVersion = 3

    package let version: Int
    package let signature: String
    package let wasCached: Bool
    package let resultExitCode: Int32
    package let reasonCodes: [ValidationReasonCode]
    package let signatureMetrics: ValidationSignatureMetrics
    package let fileChanges: ValidationFileChangeDetails
    package let invocationMetrics: ValidationInvocationMetrics
    package let liveRunMetrics: ValidationLiveRunMetrics
    package let issues: [ValidationIssue]
    package let humanSummarySource: String

    package init(
        version: Int = currentVersion,
        signature: String,
        wasCached: Bool,
        resultExitCode: Int32,
        reasonCodes: [ValidationReasonCode],
        signatureMetrics: ValidationSignatureMetrics,
        fileChanges: ValidationFileChangeDetails,
        invocationMetrics: ValidationInvocationMetrics,
        liveRunMetrics: ValidationLiveRunMetrics,
        issues: [ValidationIssue],
        humanSummarySource: String
    ) {
        self.version = version
        self.signature = signature
        self.wasCached = wasCached
        self.resultExitCode = resultExitCode
        self.reasonCodes = reasonCodes
        self.signatureMetrics = signatureMetrics
        self.fileChanges = fileChanges
        self.invocationMetrics = invocationMetrics
        self.liveRunMetrics = liveRunMetrics
        self.issues = issues
        self.humanSummarySource = humanSummarySource
    }
}

package enum ValidationLogging {
    package static func isVerboseEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        isTruthy(environment["INNODI_VALIDATION_VERBOSE"]) || isTruthy(environment["INNODI_VALIDATION_DEBUG"])
    }

    package static func renderSummary(for artifact: ValidationMetricsArtifact) -> String {
        [
            "[InnoDI] signature=\(artifact.signature)",
            "cached=\(artifact.wasCached ? "yes" : "no")",
            "reasons=\(artifact.reasonCodes.map(\.rawValue).joined(separator: ","))",
            "scanned=\(artifact.signatureMetrics.scannedFileCount)",
            "hits=\(artifact.signatureMetrics.cacheHitCount)",
            "misses=\(artifact.signatureMetrics.cacheMissCount)",
            "metadata-hit=\(artifact.signatureMetrics.metadataCacheHitCount)",
            "content-reuse=\(artifact.signatureMetrics.contentHashReuseCount)",
            "ast-reparse=\(artifact.signatureMetrics.astReparseCount)",
            "new-files=\(artifact.fileChanges.newFiles.count)",
            "deleted-files=\(artifact.fileChanges.deletedFiles.count)",
            "custom-init-ms=\(formatMilliseconds(artifact.liveRunMetrics.customInitValidationMilliseconds))",
            "semantic-ms=\(formatMilliseconds(artifact.liveRunMetrics.semanticValidationMilliseconds))",
            "dag-ms=\(formatMilliseconds(artifact.liveRunMetrics.dagValidationMilliseconds))",
            "signature-ms=\(formatMilliseconds(artifact.invocationMetrics.signatureCollectionMilliseconds))",
            "total-ms=\(formatMilliseconds(artifact.invocationMetrics.totalCoordinatorMilliseconds))",
            "issues=\(artifact.issues.count)"
        ].joined(separator: " ") + "\n"
    }

    package static func renderMarkdownSummary(for artifact: ValidationMetricsArtifact) -> String {
        var lines: [String] = [
            "# InnoDI Validation Summary",
            "",
            "- Signature: `\(artifact.signature)`",
            "- Cached: `\(artifact.wasCached ? "yes" : "no")`",
            "- Exit code: `\(artifact.resultExitCode)`",
            "- Human summary source: `\(artifact.humanSummarySource)`",
            ""
        ]

        if artifact.reasonCodes.isEmpty {
            lines.append("- Cache / run reasons: none")
        } else {
            lines.append("- Cache / run reasons:")
            for reason in artifact.reasonCodes {
                lines.append("  - `\(reason.rawValue)`: \(reasonDescription(reason))")
            }
        }

        lines.append("")
        lines.append("## Counts")
        lines.append("")
        lines.append("- Scanned files: `\(artifact.signatureMetrics.scannedFileCount)`")
        lines.append("- Metadata hits: `\(artifact.signatureMetrics.metadataCacheHitCount)`")
        lines.append("- Content-hash reuses: `\(artifact.signatureMetrics.contentHashReuseCount)`")
        lines.append("- AST reparses: `\(artifact.signatureMetrics.astReparseCount)`")
        lines.append("")
        lines.append("## File Changes")
        lines.append("")
        lines.append(contentsOf: renderFileSection(title: "New files", files: artifact.fileChanges.newFiles))
        lines.append(contentsOf: renderFileSection(title: "Deleted files", files: artifact.fileChanges.deletedFiles))
        lines.append(contentsOf: renderFileSection(title: "Reparsed files", files: artifact.fileChanges.reparsedFiles))
        lines.append(contentsOf: renderFileSection(title: "Content-hash reused files", files: artifact.fileChanges.contentHashReusedFiles))
        if !artifact.fileChanges.fallbackMatchedReferences.isEmpty {
            lines.append("")
            lines.append("### Semantic fallback matches")
            lines.append("")
            for reference in artifact.fileChanges.fallbackMatchedReferences.prefix(10) {
                lines.append("- `\(reference)`")
            }
            if artifact.fileChanges.fallbackMatchedReferences.count > 10 {
                lines.append("- ... and \(artifact.fileChanges.fallbackMatchedReferences.count - 10) more")
            }
        }
        lines.append("")
        lines.append("## Timings")
        lines.append("")
        lines.append("- Signature collection: `\(formatMilliseconds(artifact.invocationMetrics.signatureCollectionMilliseconds)) ms`")
        lines.append("- Custom init validation: `\(formatMilliseconds(artifact.liveRunMetrics.customInitValidationMilliseconds)) ms`")
        lines.append("- Semantic validation: `\(formatMilliseconds(artifact.liveRunMetrics.semanticValidationMilliseconds)) ms`")
        lines.append("- DAG validation: `\(formatMilliseconds(artifact.liveRunMetrics.dagValidationMilliseconds)) ms`")
        lines.append("- Total coordinator: `\(formatMilliseconds(artifact.invocationMetrics.totalCoordinatorMilliseconds)) ms`")
        lines.append("")
        lines.append(ValidationIssueRenderer.renderMarkdown(issues: artifact.issues))
        lines.append("")

        return lines.joined(separator: "\n")
    }
}

package func validationNow() -> TimeInterval {
    ProcessInfo.processInfo.systemUptime
}

package func validationElapsedMilliseconds(since startTime: TimeInterval) -> Double {
    max(0, (validationNow() - startTime) * 1_000)
}

private func isTruthy(_ value: String?) -> Bool {
    guard let value else {
        return false
    }

    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "1", "true", "yes", "on", "debug", "verbose":
        return true
    default:
        return false
    }
}

private func formatMilliseconds(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private func reasonDescription(_ reason: ValidationReasonCode) -> String {
    switch reason {
    case .cacheHitMetadata:
        return "All scanned files reused their cached AST digests from unchanged file metadata."
    case .cacheHitContentHash:
        return "At least one file changed metadata but reused its cached AST digest after a raw content hash match."
    case .cacheMissContentChanged:
        return "At least one file changed content and required a fresh AST parse."
    case .cacheMissNewFile:
        return "A newly discovered Swift source file invalidated the previous signature cache."
    case .cacheMissDeletedFile:
        return "A previously cached Swift source file disappeared and forced a signature recomputation."
    case .cacheMissManifestVersion:
        return "The AST digest manifest version changed, so the cache was rebuilt from scratch."
    case .staleLockRecovered:
        return "A stale validation coordinator lock was detected and removed before the live run continued."
    case .lockContentionTimeout:
        return "The validation coordinator timed out waiting for an active lock to clear."
    case .liveRunCustomInitFailure:
        return "The live validation run stopped after a structured cross-file custom init failure."
    case .liveRunSemanticValidation:
        return "The live validation run completed the semantic validator before DAG validation."
    case .liveRunSemanticFailure:
        return "The live validation run stopped after a structured semantic validation failure."
    case .liveRunDAGValidation:
        return "The live validation run executed the DAG validator."
    }
}

private func renderFileSection(title: String, files: [String]) -> [String] {
    var lines = ["### \(title)", ""]
    if files.isEmpty {
        lines.append("- none")
        return lines + [""]
    }

    for file in files.prefix(10) {
        lines.append("- `\(file)`")
    }
    if files.count > 10 {
        lines.append("- ... and \(files.count - 10) more")
    }
    return lines + [""]
}
