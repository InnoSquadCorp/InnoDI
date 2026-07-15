import Foundation

// MARK: - CLI runner helpers
//
// Shared between `DependencyGraphCLITests` (integration/substring assertions)
// and `GraphRendererSnapshotTests` (stdout snapshot assertions). Kept file-
// internal to the test target so the snapshot file can reuse the exact same
// invocation pipeline without duplicating the process plumbing.

struct CLIRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

struct ExecutableNotFound: Error, LocalizedError {
    let searchedPaths: [String]

    init(searchedPaths: [String]) {
        self.searchedPaths = searchedPaths
    }

    var errorDescription: String? {
        "Could not find InnoDI-DependencyGraph executable. Searched paths: \(searchedPaths.joined(separator: ", "))"
    }
}

final class DataSink: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

func runCLI(_ arguments: [String]) throws -> CLIRunResult {
    let process = Process()
    process.executableURL = try dependencyGraphExecutableURL()
    process.arguments = arguments
    process.currentDirectoryURL = packageRootURL()

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()
    defer {
        stdoutPipe.fileHandleForReading.closeFile()
        stderrPipe.fileHandleForReading.closeFile()
    }

    let readGroup = DispatchGroup()
    let stdoutSink = DataSink()
    let stderrSink = DataSink()

    readGroup.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        stdoutSink.set(data)
        readGroup.leave()
    }

    readGroup.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        stderrSink.set(data)
        readGroup.leave()
    }

    process.waitUntilExit()
    readGroup.wait()

    let finalStdout = stdoutSink.get()
    let finalStderr = stderrSink.get()

    return CLIRunResult(
        exitCode: process.terminationStatus,
        stdout: String(data: finalStdout, encoding: .utf8) ?? "",
        stderr: String(data: finalStderr, encoding: .utf8) ?? ""
    )
}

func dependencyGraphExecutableURL() throws -> URL {
    let fileManager = FileManager.default
    let buildURL = packageRootURL().appendingPathComponent(".build", isDirectory: true)

    // `swift test --scratch-path ...` places the CLI beside the test bundle,
    // not under the repository's `.build`. Walk upward from the running test
    // executable first so the integration test always launches the binary
    // produced by the same build instead of a stale default-scratch artifact.
    var runtimeBuildCandidates: [URL] = []
    func appendAncestorCandidates(startingAt url: URL) {
        var directory = url.standardizedFileURL
        if !directory.hasDirectoryPath {
            directory.deleteLastPathComponent()
        }
        for _ in 0..<6 {
            runtimeBuildCandidates.append(
                directory.appendingPathComponent("InnoDI-DependencyGraph")
            )
            directory.deleteLastPathComponent()
        }
    }

    appendAncestorCandidates(
        startingAt: URL(fileURLWithPath: CommandLine.arguments[0])
    )
    appendAncestorCandidates(startingAt: Bundle.main.bundleURL)

    if let scratchIndex = CommandLine.arguments.firstIndex(of: "--scratch-path"),
       CommandLine.arguments.indices.contains(scratchIndex + 1) {
        let scratchURL = URL(
            fileURLWithPath: CommandLine.arguments[scratchIndex + 1],
            isDirectory: true
        )
        runtimeBuildCandidates.append(
            scratchURL.appendingPathComponent("debug/InnoDI-DependencyGraph")
        )
    }
    if let bundleIndex = CommandLine.arguments.firstIndex(of: "--test-bundle-path"),
       CommandLine.arguments.indices.contains(bundleIndex + 1) {
        appendAncestorCandidates(
            startingAt: URL(fileURLWithPath: CommandLine.arguments[bundleIndex + 1])
        )
    }

    let directCandidates = runtimeBuildCandidates + [
        buildURL.appendingPathComponent("debug/InnoDI-DependencyGraph"),
        buildURL.appendingPathComponent("arm64-apple-macosx/debug/InnoDI-DependencyGraph"),
        buildURL.appendingPathComponent("x86_64-apple-macosx/debug/InnoDI-DependencyGraph")
    ]

    for candidate in directCandidates where fileManager.isExecutableFile(atPath: candidate.path(percentEncoded: false)) {
        return candidate
    }

    if let enumerator = fileManager.enumerator(
        at: buildURL,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) {
        for case let url as URL in enumerator {
            let path = url.path(percentEncoded: false)
            if path.hasSuffix("/debug/InnoDI-DependencyGraph"), fileManager.isExecutableFile(atPath: path) {
                return url
            }
        }
    }

    let searchedPaths = directCandidates.map { $0.path(percentEncoded: false) } + [buildURL.path(percentEncoded: false)]
    throw ExecutableNotFound(searchedPaths: searchedPaths)
}

func packageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CLIRunner.swift
        .deletingLastPathComponent() // InnoDIDependencyGraphCLITests
        .deletingLastPathComponent() // Tests
}
