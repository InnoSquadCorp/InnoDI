//
//  CacheStats.swift
//  InnoDI-DependencyGraph
//
//  Implements the `--cache-stats` subcommand. Walks a state
//  directory for `dag-validation-metrics.json` artifacts written by the
//  validation coordinator and aggregates them into a hit/miss table
//  plus per-reason-code counts. Helpful when a CI image has cache
//  rules that look right on paper but mysteriously never reuse work.
//

import Foundation
import InnoDIBuildSupport

/// Entry point invoked by `runDependencyGraphCLI` when the user
/// passed `--cache-stats`.
internal func runCacheStatsSubcommand(
    rootPath: String,
    requestedStatePath: String
) -> Int32 {
    let resolvedState = resolveStateDirectory(
        rootPath: rootPath,
        requested: requestedStatePath
    )

    var lines: [String] = []
    lines.append("InnoDI cache statistics")
    lines.append("  state path:    \(resolvedState.path(percentEncoded: false))")

    let directoryExists = FileManager.default.fileExists(atPath: resolvedState.path(percentEncoded: false))
    if !directoryExists {
        lines.append("  status:        directory does not exist (no cache to inspect)")
        print(lines.joined(separator: "\n"))
        return ExitCode.success
    }

    let artifacts = discoverValidationMetricsArtifacts(under: resolvedState)
    if artifacts.isEmpty {
        lines.append("  status:        no dag-validation-metrics.json files found")
        print(lines.joined(separator: "\n"))
        return ExitCode.success
    }

    let stats = aggregateCacheStats(artifacts: artifacts)
    lines.append("  artifacts:     \(stats.totalArtifacts)")
    lines.append("")
    lines.append("Cache hit ratio:")
    lines.append("  cached:        \(stats.cachedCount) (\(formatPercentage(stats.cachedCount, of: stats.totalArtifacts)))")
    lines.append("  live:          \(stats.liveCount) (\(formatPercentage(stats.liveCount, of: stats.totalArtifacts)))")

    if !stats.reasonCodeCounts.isEmpty {
        lines.append("")
        lines.append("Reason codes (one run can contribute multiple):")
        for (reason, count) in stats.reasonCodeCounts.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append("  \(reason.rawValue.padding(toLength: 32, withPad: " ", startingAt: 0)) \(count)")
        }
    }

    if !stats.signatureScanTotals.isZero {
        lines.append("")
        lines.append("Signature collection (sum across runs):")
        let totals = stats.signatureScanTotals
        lines.append("  scanned files:       \(totals.scannedFileCount)")
        lines.append("  metadata cache hits: \(totals.metadataCacheHitCount)")
        lines.append("  content-hash reuses: \(totals.contentHashReuseCount)")
        lines.append("  AST reparses:        \(totals.astReparseCount)")
    }

    lines.append("")
    lines.append("Reference: https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDI/InnoDI.docc/MigrationGuide.md")

    print(lines.joined(separator: "\n"))
    return ExitCode.success
}

// MARK: - Helpers

private func resolveStateDirectory(rootPath: String, requested: String) -> URL {
    let trimmed = requested.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty {
        return URL(fileURLWithPath: rootPath, isDirectory: true)
            .appendingPathComponent(".build", isDirectory: true)
    }
    if (trimmed as NSString).isAbsolutePath {
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }
    return URL(fileURLWithPath: rootPath, isDirectory: true)
        .appendingPathComponent(trimmed, isDirectory: true)
}

internal func discoverValidationMetricsArtifacts(
    under directory: URL,
    warningHandler: (String) -> Void = { message in
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
) -> [ValidationMetricsArtifact] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    let decoder = JSONDecoder()
    var artifacts: [ValidationMetricsArtifact] = []
    for case let url as URL in enumerator {
        let name = url.lastPathComponent
        guard name == "dag-validation-metrics.json" else {
            continue
        }
        guard let data = try? Data(contentsOf: url) else { continue }
        do {
            let artifact = try decoder.decode(ValidationMetricsArtifact.self, from: data)
            artifacts.append(artifact)
        } catch {
            warningHandler(
                "InnoDI: failed to decode validation metrics artifact at \(url.absoluteString): \(error)"
            )
            continue
        }
    }
    return artifacts
}

internal struct CacheStatsAggregate: Equatable {
    let totalArtifacts: Int
    let cachedCount: Int
    let liveCount: Int
    let reasonCodeCounts: [ValidationReasonCode: Int]
    let signatureScanTotals: SignatureScanTotals
}

internal struct SignatureScanTotals: Equatable {
    let scannedFileCount: Int
    let metadataCacheHitCount: Int
    let contentHashReuseCount: Int
    let astReparseCount: Int

    var isZero: Bool {
        scannedFileCount == 0
            && metadataCacheHitCount == 0
            && contentHashReuseCount == 0
            && astReparseCount == 0
    }

    static let zero = SignatureScanTotals(
        scannedFileCount: 0,
        metadataCacheHitCount: 0,
        contentHashReuseCount: 0,
        astReparseCount: 0
    )
}

/// Aggregates a slice of validation-metrics artifacts into a single
/// statistics record. Pure — exposed for unit testing without
/// touching the filesystem.
internal func aggregateCacheStats(artifacts: [ValidationMetricsArtifact]) -> CacheStatsAggregate {
    var cachedCount = 0
    var reasonCodeCounts: [ValidationReasonCode: Int] = [:]
    var scannedFileCount = 0
    var metadataCacheHitCount = 0
    var contentHashReuseCount = 0
    var astReparseCount = 0

    for artifact in artifacts {
        if artifact.wasCached {
            cachedCount += 1
        }
        for reason in artifact.reasonCodes {
            reasonCodeCounts[reason, default: 0] += 1
        }
        scannedFileCount += artifact.signatureMetrics.scannedFileCount
        metadataCacheHitCount += artifact.signatureMetrics.metadataCacheHitCount
        contentHashReuseCount += artifact.signatureMetrics.contentHashReuseCount
        astReparseCount += artifact.signatureMetrics.astReparseCount
    }

    return CacheStatsAggregate(
        totalArtifacts: artifacts.count,
        cachedCount: cachedCount,
        liveCount: artifacts.count - cachedCount,
        reasonCodeCounts: reasonCodeCounts,
        signatureScanTotals: SignatureScanTotals(
            scannedFileCount: scannedFileCount,
            metadataCacheHitCount: metadataCacheHitCount,
            contentHashReuseCount: contentHashReuseCount,
            astReparseCount: astReparseCount
        )
    )
}

private func formatPercentage(_ numerator: Int, of denominator: Int) -> String {
    guard denominator > 0 else { return "n/a" }
    let pct = Double(numerator) / Double(denominator) * 100
    return String(format: "%.1f%%", pct)
}
