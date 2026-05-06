import Foundation
import Testing
import InnoDIBuildSupport

@testable import InnoDIDependencyGraphCLI

@Suite("--cache-stats argument parsing")
struct CacheStatsArgumentsTests {
    @Test("Bare --cache-stats sets the sentinel empty path")
    func bareCacheStats() {
        guard case let .parsed(args, _) = parseArguments(["--cache-stats"]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.cacheStatsPath == "")
        #expect(args.diagnoseLockPath == nil)
    }

    @Test("--cache-stats with a positional path captures it verbatim")
    func cacheStatsWithPath() {
        guard case let .parsed(args, _) = parseArguments(["--cache-stats", "/tmp/cache"]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.cacheStatsPath == "/tmp/cache")
    }

    @Test("--cache-stats does not consume an option-shaped next argument")
    func cacheStatsDoesNotEatNextOption() {
        guard case let .parsed(args, _) = parseArguments([
            "--cache-stats",
            "--format", "json"
        ]) else {
            Issue.record("Expected parsed result")
            return
        }
        #expect(args.cacheStatsPath == "")
        #expect(args.format == .json)
    }
}

@Suite("--cache-stats artifact discovery")
struct CacheStatsArtifactDiscoveryTests {
    @Test("Discovery ignores shared-run records and warns on DAG artifact decode failures")
    func ignoresSharedRunRecordsAndWarnsOnDecodeFailures() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-cache-stats-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try Data(#"{"version":4}"#.utf8).write(
            to: directory.appendingPathComponent("validation-metrics.json")
        )
        let brokenDAGArtifact = directory.appendingPathComponent("dag-validation-metrics.json")
        try Data("not-json".utf8).write(to: brokenDAGArtifact)

        var warnings: [String] = []
        let artifacts = discoverValidationMetricsArtifacts(under: directory) { warning in
            warnings.append(warning)
        }

        #expect(artifacts.isEmpty)
        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("failed to decode validation metrics artifact") == true)
        #expect(warnings.first?.contains("file://") == true)
        #expect(warnings.first?.contains(brokenDAGArtifact.lastPathComponent) == true)
    }
}

@Suite("aggregateCacheStats — pure aggregation")
struct AggregateCacheStatsTests {

    /// Builds a `ValidationMetricsArtifact` via JSON decoding because
    /// the package's metrics sub-structs do not expose public/package
    /// memberwise initializers. The schema is owned by
    /// `Sources/InnoDIBuildSupport/ValidationMetrics.swift`; if this
    /// helper stops decoding, that's the file that changed shape and
    /// this test surfaces the regression.
    private func makeArtifact(
        wasCached: Bool,
        reasonCodes: [String],
        scanned: Int = 0,
        metadataHits: Int = 0,
        contentReuses: Int = 0,
        astReparses: Int = 0
    ) throws -> ValidationMetricsArtifact {
        let payload: [String: Any] = [
            "version": ValidationMetricsArtifact.currentVersion,
            "signature": "test",
            "wasCached": wasCached,
            "resultExitCode": 0,
            "reasonCodes": reasonCodes,
            "signatureMetrics": [
                "scannedFileCount": scanned,
                "metadataCacheHitCount": metadataHits,
                "contentHashReuseCount": contentReuses,
                "astReparseCount": astReparses,
            ],
            "fileChanges": [
                "newFiles": [],
                "deletedFiles": [],
                "reparsedFiles": [],
                "contentHashReusedFiles": [],
                "fallbackMatchedReferences": [],
            ],
            "invocationMetrics": [
                "signatureCollectionMilliseconds": 0,
                "totalCoordinatorMilliseconds": 0,
            ],
            "liveRunMetrics": [
                "customInitValidationMilliseconds": 0,
                "semanticValidationMilliseconds": 0,
                "hierarchyValidationMilliseconds": 0,
                "dagValidationMilliseconds": 0,
            ],
            "issues": [],
            "humanSummarySource": "validation-summary.md",
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try JSONDecoder().decode(ValidationMetricsArtifact.self, from: data)
    }

    @Test("Empty artifact list yields zero stats")
    func emptyArtifacts() {
        let stats = aggregateCacheStats(artifacts: [])
        #expect(stats.totalArtifacts == 0)
        #expect(stats.cachedCount == 0)
        #expect(stats.liveCount == 0)
        #expect(stats.reasonCodeCounts.isEmpty)
        #expect(stats.signatureScanTotals.isZero)
    }

    @Test("Cached + live mix tallies independently")
    func mixedCachedAndLive() throws {
        let stats = aggregateCacheStats(artifacts: [
            try makeArtifact(wasCached: true,  reasonCodes: ["cache-hit-metadata"]),
            try makeArtifact(wasCached: true,  reasonCodes: ["cache-hit-content-hash"]),
            try makeArtifact(wasCached: false, reasonCodes: ["live-run-dag-validation"]),
        ])
        #expect(stats.totalArtifacts == 3)
        #expect(stats.cachedCount == 2)
        #expect(stats.liveCount == 1)
    }

    @Test("Reason codes sum across runs")
    func reasonCodesSum() throws {
        let stats = aggregateCacheStats(artifacts: [
            try makeArtifact(wasCached: true,  reasonCodes: ["cache-hit-metadata", "live-run-semantic-validation"]),
            try makeArtifact(wasCached: false, reasonCodes: ["live-run-semantic-validation", "live-run-dag-validation"]),
            try makeArtifact(wasCached: false, reasonCodes: ["live-run-semantic-validation", "live-run-hierarchy-validation", "live-run-dag-validation"]),
        ])
        #expect(stats.reasonCodeCounts[.cacheHitMetadata] == 1)
        #expect(stats.reasonCodeCounts[.liveRunSemanticValidation] == 3)
        #expect(stats.reasonCodeCounts[.liveRunHierarchyValidation] == 1)
        #expect(stats.reasonCodeCounts[.liveRunDAGValidation] == 2)
    }

    @Test("Signature scan totals add up across runs")
    func signatureScanTotalsAddUp() throws {
        let stats = aggregateCacheStats(artifacts: [
            try makeArtifact(
                wasCached: true,  reasonCodes: [],
                scanned: 100, metadataHits: 95, contentReuses: 4, astReparses: 1
            ),
            try makeArtifact(
                wasCached: false, reasonCodes: [],
                scanned: 102, metadataHits: 80, contentReuses: 12, astReparses: 10
            ),
        ])
        #expect(stats.signatureScanTotals.scannedFileCount == 202)
        #expect(stats.signatureScanTotals.metadataCacheHitCount == 175)
        #expect(stats.signatureScanTotals.contentHashReuseCount == 16)
        #expect(stats.signatureScanTotals.astReparseCount == 11)
    }
}
