import Foundation
import Testing

@Suite("DependencyGraph CLI Integration")
struct DependencyGraphCLITests {
    @Test("Renders mermaid, dot, and ascii formats")
    func rendersSupportedFormats() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let rootPath = fixtureURL.path(percentEncoded: false)

        let mermaid = try runCLI(["--root", rootPath, "--format", "mermaid"])
        #expect(mermaid.exitCode == 0)
        #expect(mermaid.stdout.contains("graph TD"))

        let dot = try runCLI(["--root", rootPath, "--format", "dot"])
        #expect(dot.exitCode == 0)
        #expect(dot.stdout.contains("digraph InnoDI"))

        let ascii = try runCLI(["--root", rootPath, "--format", "ascii"])
        #expect(ascii.exitCode == 0)
        #expect(ascii.stdout.contains("InnoDI Dependency Graph"))
    }

    @Test("Writes graph output file with --output")
    func writesOutputFile() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let outputURL = fixtureURL.appendingPathComponent("graph.dot")
        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "dot",
            "--output", outputURL.path(percentEncoded: false)
        ])

        #expect(result.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(content.contains("digraph InnoDI"))
    }

    @Test("Unknown option emits warning but continues")
    func unknownOptionWarnsAndContinues() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--unknown",
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stderr.contains("Warning: unrecognized option '--unknown'"))
        #expect(result.stdout.contains("InnoDI Dependency Graph"))
    }

    @Test("Missing value for --root fails with usage")
    func missingRootValueFailsWithUsage() throws {
        let result = try runCLI([
            "--root",
            "--format", "ascii"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Option --root requires a value"))
        #expect(result.stdout.contains("Usage: InnoDI-DependencyGraph"))
    }

    @Test("Invalid --format value fails with usage")
    func invalidFormatValueFailsWithUsage() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "invalid"
        ])

        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("Invalid --format value 'invalid'"))
        #expect(result.stdout.contains("Usage: InnoDI-DependencyGraph"))
    }

    @Test("PNG output handles Graphviz availability")
    func pngOutputHandlesGraphvizAvailability() throws {
        let fixtureURL = try makeFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let outputURL = fixtureURL.appendingPathComponent("graph.png")
        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "dot",
            "--output", outputURL.path(percentEncoded: false)
        ])

        if result.exitCode == 0 {
            #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
            #expect(result.stdout.contains("PNG generated at"))
        } else {
            #expect(result.exitCode == 1)
            #expect(
                result.stderr.contains("dot command not found") || result.stderr.contains("Failed to generate PNG")
            )
        }
    }

    @Test("No container output write failure returns distinct exit code")
    func noContainerWriteFailureReturnsDistinctExitCode() throws {
        let fixtureURL = try makeNoContainerFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--format", "ascii",
            "--output", "/dev/null/nope.txt"
        ])

        #expect(result.exitCode == 2)
        #expect(result.stderr.contains("Error writing to file"))
    }

    @Test("Validate DAG fails on container cycle")
    func validateDAGFailsOnCycle() throws {
        let fixtureURL = try makeCycleFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("DAG validation failed."))
        #expect(result.stderr.contains("Detected dependency cycles:"))
    }

    @Test("Validate DAG ignores opted-out containers")
    func validateDAGIgnoresOptedOutContainers() throws {
        let fixtureURL = try makeValidateDAGOptOutFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("DAG validation passed."))
    }

    @Test("Validate DAG fails on ambiguous container reference")
    func validateDAGFailsOnAmbiguousContainerReference() throws {
        let fixtureURL = try makeAmbiguousReferenceFixtureProject()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--validate-dag"
        ])

        #expect(result.exitCode == 3)
        #expect(result.stderr.contains("Ambiguous container references:"))
        #expect(result.stderr.contains("FeatureContainer"))
    }
}

private struct CLIRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

private struct ExecutableNotFound: Error, LocalizedError {
    let searchedPaths: [String]

    init(searchedPaths: [String]) {
        self.searchedPaths = searchedPaths
    }

    var errorDescription: String? {
        "Could not find InnoDI-DependencyGraph executable. Searched paths: \(searchedPaths.joined(separator: ", "))"
    }
}

private final class DataSink: @unchecked Sendable {
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

private func runCLI(_ arguments: [String]) throws -> CLIRunResult {
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

private func dependencyGraphExecutableURL() throws -> URL {
    let fileManager = FileManager.default
    let buildURL = packageRootURL().appendingPathComponent(".build", isDirectory: true)

    let directCandidates = [
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

private func packageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // DependencyGraphCLITests.swift
        .deletingLastPathComponent() // InnoDIDependencyGraphCLITests
        .deletingLastPathComponent() // Tests
}

private func makeFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Fixture-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let appContainerSource = """
    import InnoDI

    protocol APIClientProtocol {}
    struct APIClient: APIClientProtocol {}

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.input)
        var baseURL: String

        @Provide(.shared, factory: APIClient())
        var apiClient: any APIClientProtocol
    }
    """

    let featureContainerSource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var apiClient: any APIClientProtocol
    }

    func buildFeature(apiClient: any APIClientProtocol) {
        _ = FeatureContainer(apiClient: apiClient)
    }
    """

    try appContainerSource.write(
        to: fixtureURL.appendingPathComponent("AppContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    try featureContainerSource.write(
        to: fixtureURL.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeNoContainerFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-NoContainer-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    struct PlainType {
        let value: Int
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("Plain.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeCycleFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Cycle-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }

    @DIContainer
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("Cycle.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeValidateDAGOptOutFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Cycle-OptOut-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let source = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }

    @DIContainer(validateDAG: false)
    struct FeatureContainer {
        @Provide(.shared, factory: AppContainer(), concrete: true)
        var app: AppContainer
    }
    """

    try source.write(
        to: fixtureURL.appendingPathComponent("CycleOptOut.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}

private func makeAmbiguousReferenceFixtureProject() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Ambiguous-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)
    let featureADirectory = fixtureURL.appendingPathComponent("FeatureA", isDirectory: true)
    let featureBDirectory = fixtureURL.appendingPathComponent("FeatureB", isDirectory: true)
    try FileManager.default.createDirectory(at: featureADirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: featureBDirectory, withIntermediateDirectories: true)

    let appSource = """
    import InnoDI

    @DIContainer(root: true)
    struct AppContainer {
        @Provide(.shared, factory: FeatureContainer(), concrete: true)
        var feature: FeatureContainer
    }
    """

    let featureASource = """
    import InnoDI

    @DIContainer
    struct FeatureContainer {
        @Provide(.input)
        var value: Int
    }
    """

    let featureBSource = """
    import InnoDI

    enum Namespace {
        @DIContainer
        struct FeatureContainer {
            @Provide(.input)
            var value: String
        }
    }
    """

    try appSource.write(
        to: fixtureURL.appendingPathComponent("App.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureASource.write(
        to: featureADirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )
    try featureBSource.write(
        to: featureBDirectory.appendingPathComponent("FeatureContainer.swift"),
        atomically: true,
        encoding: .utf8
    )

    return fixtureURL
}
