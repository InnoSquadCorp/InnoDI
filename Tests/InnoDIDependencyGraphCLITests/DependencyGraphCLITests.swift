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
}

private struct CLIRunResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
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
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return CLIRunResult(
        exitCode: process.terminationStatus,
        stdout: String(data: stdoutData, encoding: .utf8) ?? "",
        stderr: String(data: stderrData, encoding: .utf8) ?? ""
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

    struct ExecutableNotFound: Error {}
    throw ExecutableNotFound()
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
