//
//  ValidationCoordinator+Caching.swift
//  InnoDIBuildSupport
//
//  Filesystem IO for the shared-run cache that the coordinator relies on to
//  reuse one live validation across parallel build-plugin invocations. These
//  helpers read/write the JSON artifacts inside the shared-run directory
//  (`result.json`, `validation-metrics.json`, `validation-summary.md`) and
//  prune stale signature subdirectories so state doesn't grow unbounded.
//
//  Splitting them out keeps `ValidationCoordinator.swift` focused on the
//  orchestration pipeline (coordinate → lock → execute).
//

import Foundation

internal func loadCachedSharedRun(
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

internal func loadCachedResult(at url: URL) -> ValidationCommandResult? {
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

internal func persistResult(_ result: ValidationCommandResult, to url: URL) throws {
    let data = try JSONEncoder().encode(result)
    try data.write(to: url, options: .atomic)
}

internal func writeStamp(signature: String, result: ValidationCommandResult, to outputDirectoryURL: URL) throws {
    let stampURL = outputDirectoryURL.appendingPathComponent("dag-validation-stamp.txt")
    let content = "signature=\(signature)\nexitCode=\(result.exitCode)\n"
    try content.write(to: stampURL, atomically: true, encoding: .utf8)
}

internal func persistMetricsArtifact(_ artifact: ValidationMetricsArtifact, to url: URL) throws {
    let data = try JSONEncoder().encode(artifact)
    try data.write(to: url, options: .atomic)
}

internal func loadSharedRunRecord(at url: URL) -> SharedValidationRunRecord? {
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

internal func persistSharedRunRecord(_ record: SharedValidationRunRecord, to url: URL) throws {
    let data = try JSONEncoder().encode(record)
    try data.write(to: url, options: .atomic)
}

internal func persistSummaryReport(_ content: String, to url: URL) throws {
    try content.write(to: url, atomically: true, encoding: .utf8)
}

internal func pruneSharedRunDirectories(keepingDirectoryName directoryName: String, in stateDirectoryURL: URL) throws {
    let fileManager = FileManager.default
    let entries = try fileManager.contentsOfDirectory(
        at: stateDirectoryURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )

    for entry in entries {
        let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true,
              entry.lastPathComponent != directoryName,
              isPrunableSharedRunDirectoryName(entry.lastPathComponent),
              !isSharedRunLockCurrentlyHeld(inDirectory: entry) else {
            continue
        }
        // A holder acquiring the lock between the probe and this removal
        // remains possible without a global lock; the outcome stays
        // fail-closed (spurious revalidation), never stale data.
        try? fileManager.removeItem(at: entry)
    }
}

private func isPrunableSharedRunDirectoryName(_ name: String) -> Bool {
    if isStableValidationHash(name) {
        return true
    }

    let prefix = "shared-run-v"
    guard name.hasPrefix(prefix) else {
        return false
    }
    let components = name.dropFirst(prefix.count).split(
        separator: "-",
        maxSplits: 1,
        omittingEmptySubsequences: false
    )
    guard components.count == 2,
          !components[0].isEmpty,
          components[0].utf8.allSatisfy({ (48...57).contains($0) }) else {
        return false
    }
    return isStableValidationHash(String(components[1]))
}

private func isStableValidationHash(_ value: String) -> Bool {
    value.utf8.count == 32 && value.utf8.allSatisfy { byte in
        (48...57).contains(byte) || (97...102).contains(byte)
    }
}
