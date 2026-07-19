import Foundation
import InnoDIWorkspaceAnalysis
import Testing

@testable import InnoDIBuildSupport

@Suite("ValidationContract")
struct ValidationContractTests {
    @Test("Validation metrics artifact JSON schema stays stable")
    func validationMetricsArtifactJSONGolden() throws {
        #expect(ValidationMetricsArtifact.currentVersion == 4)

        let actual = try canonicalJSONString(contractArtifact())
        #expect(actual == expectedContractArtifactJSON)
    }

    @Test("Validation Markdown summary rendering stays stable")
    func validationMarkdownSummaryGolden() {
        let actual = ValidationLogging.renderMarkdownSummary(for: contractArtifact())
        #expect(actual == expectedContractMarkdownSummary)
    }

    @Test("Shared-run cache keys stay version salted")
    func sharedRunCacheKeyUsesCurrentVersionSalt() {
        #expect(sharedRunCacheVersion == 9)
        #expect(sharedRunCacheKey(for: "abc123") == "shared-run-v9-abc123")
        #expect(sharedRunCacheKey(for: "abc123") != "shared-run-v8-abc123")
    }

    @Test("Coordinator emits decodable metrics and matching Markdown summary artifacts")
    func coordinatorEmitsCurrentContractArtifacts() async throws {
        let fixture = try makeContractFixture()
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        let runner = ContractValidationRunner(
            result: ValidationCommandResult(exitCode: 0, stdout: "DAG validation passed.\n", stderr: "")
        )

        let outcome = try await ValidationCoordinator.coordinate(
            rootPath: fixture.rootURL.path(percentEncoded: false),
            toolPath: "/usr/bin/true",
            stateDirectoryPath: fixture.stateURL.path(percentEncoded: false),
            outputDirectoryPath: fixture.outputURL.path(percentEncoded: false),
            runner: runner
        )

        let metricsURL = fixture.outputURL.appendingPathComponent("dag-validation-metrics.json")
        let summaryURL = fixture.outputURL.appendingPathComponent("dag-validation-summary.md")
        let persistedMetrics = try loadContractMetricsArtifact(at: metricsURL)
        let persistedSummary = try String(contentsOf: summaryURL, encoding: .utf8)

        #expect(persistedMetrics == outcome.metricsArtifact)
        #expect(persistedSummary == ValidationLogging.renderMarkdownSummary(for: outcome.metricsArtifact))
        #expect(persistedMetrics.version == ValidationMetricsArtifact.currentVersion)
        #expect(persistedMetrics.humanSummarySource == "dag-validation-summary.md")
    }
}

private let expectedContractArtifactJSON =
    """
    {
      "fileChanges" : {
        "contentHashReusedFiles" : [
          "Stable.swift"
        ],
        "deletedFiles" : [
          "Old.swift"
        ],
        "fallbackMatchedReferences" : [
          "App.Container",
          "Nested.Container"
        ],
        "newFiles" : [
          "New.swift"
        ],
        "reparsedFiles" : [
          "Feature.swift"
        ]
      },
      "humanSummarySource" : "dag-validation-summary.md",
      "invocationMetrics" : {
        "signatureCollectionMilliseconds" : 12.34,
        "totalCoordinatorMilliseconds" : 56.78
      },
      "issues" : [
        {
          "code" : "semantic.failure",
          "location" : {
            "column" : 3,
            "filePath" : "Feature.swift",
            "line" : 12
          },
          "message" : "Something broke",
          "metadata" : {
            "containerPath" : "AppContainer"
          },
          "notes" : [
            {
              "location" : {
                "column" : 1,
                "filePath" : "Child.swift",
                "line" : 2
              },
              "message" : "See child"
            }
          ],
          "remediation" : "Rename dependency",
          "severity" : "error"
        }
      ],
      "liveRunMetrics" : {
        "customInitValidationMilliseconds" : 1.25,
        "dagValidationMilliseconds" : 3.75,
        "hierarchyValidationMilliseconds" : 0,
        "semanticValidationMilliseconds" : 2.5
      },
      "reasonCodes" : [
        "cache-miss-content-changed",
        "live-run-semantic-validation",
        "live-run-dag-validation"
      ],
      "resultExitCode" : 1,
      "signature" : "abc123",
      "signatureMetrics" : {
        "astReparseCount" : 2,
        "contentHashReuseCount" : 2,
        "metadataCacheHitCount" : 1,
        "scannedFileCount" : 5
      },
      "version" : 4,
      "wasCached" : false
    }
    """

private let expectedContractMarkdownSummary =
    """
    # InnoDI Validation Summary

    - Signature: `abc123`
    - Cached: `no`
    - Exit code: `1`
    - Human summary source: `dag-validation-summary.md`

    - Cache / run reasons:
      - `cache-miss-content-changed`: At least one file changed content and required a fresh AST parse.
      - `live-run-semantic-validation`: The live validation run completed the semantic validator before DAG validation.
      - `live-run-dag-validation`: The live validation run executed the DAG validator.

    ## Counts

    - Scanned files: `5`
    - Metadata hits: `1`
    - Content-hash reuses: `2`
    - AST reparses: `2`

    ## File Changes

    ### New files

    - `New.swift`

    ### Deleted files

    - `Old.swift`

    ### Reparsed files

    - `Feature.swift`

    ### Content-hash reused files

    - `Stable.swift`


    ### Semantic fallback matches

    - `App.Container`
    - `Nested.Container`

    ## Timings

    - Signature collection: `12.34 ms`
    - Custom init validation: `1.25 ms`
    - Semantic validation: `2.50 ms`
    - Hierarchy validation: `0.00 ms`
    - DAG validation: `3.75 ms`
    - Total coordinator: `56.78 ms`

    ## Build Issues

    ### `[semantic.failure]` Something broke

    - Severity: `error`
    - Location: `Feature.swift:12:3`
    - Remediation: Rename dependency
    - containerPath: `AppContainer`
    - Note: See child (`Child.swift:2:1`)
    """ + "\n\n\n"

private func contractArtifact() -> ValidationMetricsArtifact {
    ValidationMetricsArtifact(
        signature: "abc123",
        wasCached: false,
        resultExitCode: 1,
        reasonCodes: [
            .cacheMissContentChanged,
            .liveRunSemanticValidation,
            .liveRunDAGValidation
        ],
        signatureMetrics: ValidationSignatureMetrics(
            scannedFileCount: 5,
            metadataCacheHitCount: 1,
            contentHashReuseCount: 2,
            astReparseCount: 2
        ),
        fileChanges: ValidationFileChangeDetails(
            newFiles: ["New.swift"],
            deletedFiles: ["Old.swift"],
            reparsedFiles: ["Feature.swift"],
            contentHashReusedFiles: ["Stable.swift"],
            fallbackMatchedReferences: ["App.Container", "Nested.Container"]
        ),
        invocationMetrics: ValidationInvocationMetrics(
            signatureCollectionMilliseconds: 12.34,
            totalCoordinatorMilliseconds: 56.78
        ),
        liveRunMetrics: ValidationLiveRunMetrics(
            customInitValidationMilliseconds: 1.25,
            semanticValidationMilliseconds: 2.5,
            hierarchyValidationMilliseconds: 0,
            dagValidationMilliseconds: 3.75
        ),
        issues: [
            ValidationIssue(
                code: "semantic.failure",
                severity: .error,
                message: "Something broke",
                location: ValidationIssueLocation(filePath: "Feature.swift", line: 12, column: 3),
                notes: [
                    ValidationIssueNote(
                        message: "See child",
                        location: ValidationIssueLocation(filePath: "Child.swift", line: 2, column: 1)
                    )
                ],
                remediation: "Rename dependency",
                metadata: ["containerPath": "AppContainer"]
            )
        ],
        humanSummarySource: "dag-validation-summary.md"
    )
}

private struct ValidationContractFixture {
    let rootURL: URL
    let stateURL: URL
    let outputURL: URL
}

private func makeContractFixture() throws -> ValidationContractFixture {
    let rootURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-ValidationContract-\(UUID().uuidString)", isDirectory: true)
    let stateURL = rootURL.appendingPathComponent("state", isDirectory: true)
    let outputURL = rootURL.appendingPathComponent("output", isDirectory: true)

    try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    try "struct Feature { let value = 1 }\n".write(
        to: rootURL.appendingPathComponent("Feature.swift"),
        atomically: true,
        encoding: .utf8
    )

    return ValidationContractFixture(
        rootURL: rootURL,
        stateURL: stateURL,
        outputURL: outputURL
    )
}

private func loadContractMetricsArtifact(at url: URL) throws -> ValidationMetricsArtifact {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ValidationMetricsArtifact.self, from: data)
}

private func canonicalJSONString<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private struct ContractValidationRunner: ValidationCommandRunning, Sendable {
    let result: ValidationCommandResult

    func runValidationTool(
        toolPath: String?,
        rootPath: String,
        snapshot: WorkspaceSourceSnapshot
    ) throws -> ValidationCommandResult {
        result
    }
}
