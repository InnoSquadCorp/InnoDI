import Foundation
import Testing

/// Asserts that `actual` matches the snapshot file named `snapshot`, resolved
/// via `snapshotFileURL(for:callerFilePath:fileExtension:)` relative to the
/// calling test file.
///
/// When `INNODI_RECORD_SNAPSHOTS=1` is set, or no snapshot file exists yet,
/// the helper writes `actual` to disk and records an Issue so the run does
/// not silently pass on first record.
///
/// Intended for text output that is NOT a Swift macro expansion — e.g. CLI
/// renderer output (Mermaid / DOT / ASCII), diagnostic logs, etc. Prefer
/// `assertMacroExpansionSnapshot` for macro expansion verification because
/// it also wires in diagnostic-count checks.
public func assertTextSnapshot(
    _ actual: String,
    matches snapshot: String,
    fileExtension: String = ".txt",
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let sourceLocation = Testing.SourceLocation(
        fileID: "\(fileID)",
        filePath: "\(filePath)",
        line: Int(line),
        column: Int(column)
    )

    let snapshotURL = snapshotFileURL(
        for: snapshot,
        callerFilePath: "\(filePath)",
        fileExtension: fileExtension
    )
    let recordMode = isSnapshotRecordModeEnabled()
    let fileExists = FileManager.default.fileExists(atPath: snapshotURL.path)

    if recordMode || !fileExists {
        do {
            try writeSnapshot(actual, to: snapshotURL)
            let message = "Recorded snapshot at \(snapshotURL.path). Re-run tests to verify."
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        } catch {
            let message = "Failed to write snapshot at \(snapshotURL.path): \(error)"
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        }
        return
    }

    do {
        let expected = try readSnapshot(at: snapshotURL)
        let actualTrimmed = trimBlankBoundaries(actual)
        let expectedTrimmed = trimBlankBoundaries(expected)
        if actualTrimmed != expectedTrimmed {
            let message = """
                Text output did not match snapshot \(snapshotURL.lastPathComponent).

                --- Expected (snapshot)
                \(expected)
                --- Actual
                \(actual)
                ---

                To update, re-run with \(innoDISnapshotRecordEnvVar)=1.
                """
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        }
    } catch {
        let message = "Failed to read snapshot at \(snapshotURL.path): \(error)"
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}
