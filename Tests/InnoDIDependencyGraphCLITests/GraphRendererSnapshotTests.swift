import Foundation
import InnoDITestSupport
import Testing

/// Snapshot regression tests for the CLI's three graph output formats:
/// Mermaid, DOT, and ASCII. Each test builds the same minimal two-container
/// fixture and snapshots the CLI stdout verbatim.
///
/// The fixture is intentionally tiny (1 root container plus 1 unrelated
/// container) so snapshot diffs stay readable while still proving rooted
/// render pruning end-to-end. Complement to `DependencyGraphCLITests` which
/// keeps broader substring-level integration assertions.
@Suite("Graph Renderer Snapshots")
struct GraphRendererSnapshotTests {
    @Test("Mermaid output for a minimal two-container fixture")
    func mermaidMinimalFixture() throws {
        let fixtureURL = try makeMinimalFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "mermaid"
        ])
        try #require(result.exitCode == 0, "CLI exited non-zero. stderr: \(result.stderr)")
        assertTextSnapshot(result.stdout, matches: "mermaidMinimalFixture")
    }

    @Test("DOT output for a minimal two-container fixture")
    func dotMinimalFixture() throws {
        let fixtureURL = try makeMinimalFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "dot"
        ])
        try #require(result.exitCode == 0, "CLI exited non-zero. stderr: \(result.stderr)")
        assertTextSnapshot(result.stdout, matches: "dotMinimalFixture")
    }

    @Test("ASCII output for a minimal two-container fixture")
    func asciiMinimalFixture() throws {
        let fixtureURL = try makeMinimalFixture()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let result = try runCLI([
            "--root", fixtureURL.path(percentEncoded: false),
            "--root-pruning", "roots",
            "--format", "ascii"
        ])
        try #require(result.exitCode == 0, "CLI exited non-zero. stderr: \(result.stderr)")
        assertTextSnapshot(result.stdout, matches: "asciiMinimalFixture")
    }
}

/// Minimal two-container fixture used by all three renderer snapshot tests.
/// Deliberately small: one root (`AppContainer`) wiring an `APIClient`
/// singleton, and one unrelated feature container (`FeatureContainer`) that
/// should disappear from rooted render output because no graph edge reaches it.
private func makeMinimalFixture() throws -> URL {
    let fixtureURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-CLI-Snapshot-\(UUID().uuidString)", isDirectory: true)

    try FileManager.default.createDirectory(at: fixtureURL, withIntermediateDirectories: true)

    let appContainerSource = """
    import InnoDI

    protocol APIClientProtocol {}
    struct APIClient: APIClientProtocol {}

    @DIContainer(root: true)
    struct AppContainer {
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
