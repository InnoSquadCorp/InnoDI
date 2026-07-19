import Foundation
import Testing

/// Shared primitives for file-backed snapshot assertions. Used by both
/// `MacroAssertions` (macro expansion snapshots under `__Snapshots__/<TestFile>/`)
/// and `TextSnapshotAssertions` (arbitrary text, e.g. CLI renderer output).
///
/// Record-mode detection and file layout are centralized here so that the two
/// assertion families cannot drift in how they resolve snapshot paths or
/// interpret `INNODI_RECORD_SNAPSHOTS=1`.

/// Environment variable that, when set to "1", makes snapshot assertions record
/// the current output to disk instead of comparing against it.
public let innoDISnapshotRecordEnvVar = "INNODI_RECORD_SNAPSHOTS"

/// Returns `true` when the caller should write the snapshot instead of
/// diffing against an existing file.
///
/// Callers should also force-record when the snapshot file does not yet exist,
/// so a fresh test can bootstrap its baseline on first run.
///
/// Record mode is decided by the environment the test process was launched
/// with (`Tools/record-*.sh` export the variable before `swift test`). The
/// `environment` parameter exists so tests can exercise the decision without
/// mutating process-global state via `setenv`, which would race the parallel
/// snapshot suites that consult this function at runtime.
public func isSnapshotRecordModeEnabled(
    environment: [String: String] = ProcessInfo.processInfo.environment
) -> Bool {
    environment[innoDISnapshotRecordEnvVar] == "1"
}

/// Resolves the on-disk URL for a snapshot named `snapshot` from the
/// calling test's file path. Layout: `<test file dir>/__Snapshots__/<test file base>/<snapshot>.<ext>`
///
/// Parameters:
/// - snapshot: bare snapshot name (no extension, no path separators).
/// - callerFilePath: `#filePath` of the test site — used to anchor the
///   `__Snapshots__` directory relative to the test file.
/// - fileExtension: file extension including the leading dot. Defaults to
///   `".swift"` to match the existing macro snapshot layout; CLI renderer
///   snapshots typically use `".txt"`.
public func snapshotFileURL(
    for snapshot: String,
    callerFilePath: String,
    fileExtension: String = ".swift"
) -> URL {
    let callerURL = URL(fileURLWithPath: callerFilePath)
    let testFileBase = callerURL.deletingPathExtension().lastPathComponent
    let testDir = callerURL.deletingLastPathComponent()
    let extensionSuffix = fileExtension.hasPrefix(".") ? fileExtension : ".\(fileExtension)"
    return testDir
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(testFileBase, isDirectory: true)
        .appendingPathComponent("\(snapshot)\(extensionSuffix)", isDirectory: false)
}

/// Writes `contents` to `url`, creating any missing intermediate directories.
/// Throws on I/O failure so the caller can surface the error via `Issue.record`.
public func writeSnapshot(_ contents: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

/// Reads snapshot contents at `url` as UTF-8. Throws on I/O failure.
public func readSnapshot(at url: URL) throws -> String {
    try String(contentsOf: url, encoding: .utf8)
}

/// Trims leading and trailing newline runs so that snapshot comparisons are
/// tolerant of a single trailing newline (or lack thereof) and empty leading
/// lines introduced by raw-string literals.
public func trimBlankBoundaries(_ source: String) -> String {
    var scalars = Substring(source)
    while let first = scalars.first, first.isNewline { scalars = scalars.dropFirst() }
    while let last = scalars.last, last.isNewline { scalars = scalars.dropLast() }
    return String(scalars)
}
