import Foundation
import Testing

@Suite("Documentation link script contracts")
struct DocumentationLinkScriptTests {
    @Test("Tracked repository documentation has no missing local targets")
    func repositoryDocumentationPasses() throws {
        let result = try runDocumentationLinkCheck(arguments: [])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("local documentation link(s)"))
    }

    @Test("Fixture accepts supported local, external, and ignored links")
    func supportedLinksPass() throws {
        let fixture = try DocumentationLinkFixture(
            readme: """
            [Guide](Docs/guide.md)
            ![Logo](<assets/logo image.png>)
            [External](https://example.com/docs)
            [Anchor](#usage)
            [Reference][guide]
            [guide]: Docs/guide.md#start
            `[Inline code](missing-inline.md)`

            ```swift
            let example = "[Code fence](missing-fence.md)"
            ```
            """
        )
        defer { fixture.remove() }

        let result = try runDocumentationLinkCheck(arguments: [
            "--root", fixture.rootURL.path,
        ])

        #expect(result.exitCode == 0)
        #expect(result.output.contains("Checked 3 local documentation link(s)"))
    }

    @Test("Missing local target fails with source location and destination")
    func missingTargetFails() throws {
        let fixture = try DocumentationLinkFixture(
            readme: "[Missing](Docs/missing.md)\n"
        )
        defer { fixture.remove() }

        let result = try runDocumentationLinkCheck(arguments: [
            "--root", fixture.rootURL.path,
        ])

        #expect(result.exitCode == 1)
        #expect(
            result.output.contains(
                "README.md:1: missing local documentation target: Docs/missing.md"
            )
        )
    }
}

private struct DocumentationLinkFixture {
    let rootURL: URL

    init(readme: String) throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-DocumentationLinks-\(UUID().uuidString)",
            isDirectory: true
        )
        let docsURL = rootURL.appendingPathComponent("Docs", isDirectory: true)
        let assetsURL = rootURL.appendingPathComponent("assets", isDirectory: true)
        try FileManager.default.createDirectory(
            at: docsURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: assetsURL,
            withIntermediateDirectories: true
        )
        try readme.write(
            to: rootURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Guide\n".write(
            to: docsURL.appendingPathComponent("guide.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0]).write(
            to: assetsURL.appendingPathComponent("logo image.png")
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private struct DocumentationLinkCommandResult {
    let exitCode: Int32
    let output: String
}

private func runDocumentationLinkCheck(
    arguments: [String]
) throws -> DocumentationLinkCommandResult {
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
        "InnoDI-DocumentationLinkOutput-\(UUID().uuidString).log"
    )
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    defer { try? FileManager.default.removeItem(at: outputURL) }

    let outputHandle = try FileHandle(forWritingTo: outputURL)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
        packageRootURL()
            .appendingPathComponent("Tools/check-docs-local-links.sh")
            .path,
    ] + arguments
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: "GIT_DIR")
    environment.removeValue(forKey: "GIT_WORK_TREE")
    process.environment = environment

    try process.run()
    process.waitUntilExit()
    try outputHandle.synchronize()
    try outputHandle.close()

    return DocumentationLinkCommandResult(
        exitCode: process.terminationStatus,
        output: try String(contentsOf: outputURL, encoding: .utf8)
    )
}
