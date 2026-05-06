//
//  DiagnoseLock.swift
//  InnoDI-DependencyGraph
//
//  Implements the `--diagnose-lock` subcommand. The CLI walks a
//  scratch directory the same way the build plugin would, classifies
//  the filesystem, reads any lock metadata it finds, and prints a
//  structured human-readable report. Useful when the build plugin
//  reports `lock-contention-timeout` or `unsafe-filesystem` and the
//  user wants to inspect the state without touching files manually.
//

import Foundation
import InnoDIBuildSupport

/// Entry point for `runDependencyGraphCLI` to dispatch into when the
/// user passed `--diagnose-lock`.
internal func runDiagnoseLockSubcommand(
    rootPath: String,
    requestedScratchPath: String,
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Int32 {
    let resolvedScratch = resolveScratchDirectory(
        rootPath: rootPath,
        requested: requestedScratchPath
    )

    var lines: [String] = []
    lines.append("InnoDI lock diagnostic")
    lines.append("  scratch path:  \(resolvedScratch.path(percentEncoded: false))")

    let directoryExists = FileManager.default.fileExists(atPath: resolvedScratch.path(percentEncoded: false))
    if !directoryExists {
        lines.append("  status:        directory does not exist (no lock files to inspect)")
    }

    // Classify the filesystem the same way the coordinator does.
    let classification = FilesystemTypeDetector.classify(directory: resolvedScratch)
    lines.append("  filesystem:    \(formatClassification(classification))")

    // Surface the operator-relevant environment variables verbatim.
    lines.append("")
    lines.append("Environment overrides:")
    for key in [
        ValidationCoordinatorLockPolicy.EnvKey.lockTimeout,
        ValidationCoordinatorLockPolicy.EnvKey.staleLockAge,
        ValidationCoordinatorLockPolicy.EnvKey.allowUnsafeLock,
    ] {
        let value = environment[key] ?? "<unset>"
        lines.append("  \(key) = \(value)")
    }

    // Discover any lock files. We look one level under the scratch
    // path because the coordinator stores them under
    // `<scratch>/<signature>/lock`.
    let lockReports = directoryExists ? discoverLockFiles(under: resolvedScratch) : []
    lines.append("")
    if lockReports.isEmpty {
        lines.append("Lock files: none found under the scratch path.")
    } else {
        lines.append("Lock files: \(lockReports.count) found")
        for report in lockReports {
            lines.append("")
            lines.append("- path:        \(report.path)")
            lines.append("  age:         \(report.age)")
            if let metadata = report.metadata {
                lines.append("  holder pid:  \(metadata.pid)")
                lines.append("  created at:  \(formatEpoch(metadata.createdAt))")
                if let bootID = metadata.bootID {
                    lines.append("  boot id:     \(bootID)")
                }
            } else {
                lines.append("  metadata:    <unavailable — file unreadable or v1 with empty payload>")
            }
        }
    }

    lines.append("")
    lines.append("Reference: https://github.com/InnoSquadCorp/InnoDI/blob/main/Sources/InnoDI/InnoDI.docc/lock-safety.md")

    print(lines.joined(separator: "\n"))
    return ExitCode.success
}

// MARK: - Helpers

private func resolveScratchDirectory(rootPath: String, requested: String) -> URL {
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

private func formatClassification(_ classification: FilesystemClassification) -> String {
    let identifier = classification.identifier.isEmpty
        ? "<unavailable>"
        : classification.identifier
    let suffix: String
    switch classification.safetyClass {
    case .safe:    suffix = "safe (O_CREAT | O_EXCL is atomic)"
    case .unsafe:  suffix = "unsafe — coordinator refuses unless INNODI_ALLOW_UNSAFE_LOCK=1"
    case .unknown: suffix = "unrecognized — coordinator proceeds with a stderr warning"
    }
    return "\(identifier) — \(suffix)"
}

private struct LockFileReport {
    let path: String
    let age: String
    let metadata: ValidationCoordinatorLockMetadata?
}

private func discoverLockFiles(under directory: URL) -> [LockFileReport] {
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else {
        return []
    }

    var reports: [LockFileReport] = []
    for case let url as URL in enumerator {
        guard url.lastPathComponent == "lock" else { continue }
        let path = url.path(percentEncoded: false)
        let now = Date()
        let ageString: String
        if let attributes = try? fileManager.attributesOfItem(atPath: path),
           let modified = (attributes[.modificationDate] as? Date) ?? (attributes[.creationDate] as? Date) {
            let age = max(0, now.timeIntervalSince(modified))
            ageString = String(format: "%.2fs", age)
        } else {
            ageString = "<unknown>"
        }
        let metadata = loadLockMetadata(at: url)
        reports.append(LockFileReport(path: path, age: ageString, metadata: metadata))
    }
    return reports.sorted(by: { $0.path < $1.path })
}

private func formatEpoch(_ epoch: TimeInterval) -> String {
    let date = Date(timeIntervalSince1970: epoch)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
