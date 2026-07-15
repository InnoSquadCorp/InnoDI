import Foundation
import Testing

@Suite("Release artifact packaging contracts")
struct ReleaseArtifactScriptTests {
    @Test("DocC archive bytes are reproducible after metadata changes")
    func deterministicDocCArchive() throws {
        let fixture = try ReleaseArtifactFixture()
        defer { fixture.remove() }

        let first = fixture.rootURL.appendingPathComponent("first.tar.gz")
        let second = fixture.rootURL.appendingPathComponent("second.tar.gz")

        try fixture.package(output: first)
        try FileManager.default.setAttributes(
            [
                .modificationDate: Date(timeIntervalSince1970: 1_800_000_000),
                .posixPermissions: 0o600,
            ],
            ofItemAtPath: fixture.sourceURL
                .appendingPathComponent("nested/payload.json").path
        )
        try fixture.package(output: second)

        #expect(try Data(contentsOf: first) == Data(contentsOf: second))

        let listing = try fixture.run(
            executable: "/usr/bin/tar",
            arguments: ["-tzf", first.path]
        )
        #expect(listing.exitCode == 0)
        #expect(
            listing.output.split(separator: "\n").map(String.init) == [
                "InnoDI/",
                "InnoDI/index.html",
                "InnoDI/nested/",
                "InnoDI/nested/payload.json",
            ]
        )
    }

    @Test("Packaging script pins every archive metadata input")
    func deterministicMetadataContract() throws {
        let source = try String(
            contentsOf: packageRootURL()
                .appendingPathComponent("Tools/package-release-docc.sh"),
            encoding: .utf8
        )

        #expect(source.contains("LC_ALL=C sort -z"))
        #expect(source.contains("touch -h -t 198001010000.00"))
        #expect(source.contains("--no-recursion"))
        #expect(source.contains("--no-xattrs"))
        #expect(source.contains("--no-mac-metadata"))
        #expect(source.contains("--no-acls"))
        #expect(source.contains("--no-fflags"))
        #expect(source.contains("--format paxr"))
        #expect(source.contains("--uid 0"))
        #expect(source.contains("--gid 0"))
        #expect(source.contains("--uname root"))
        #expect(source.contains("--gname root"))
        #expect(source.contains("gzip -n -9"))
    }
}

private struct ReleaseArtifactResult {
    let exitCode: Int32
    let output: String
}

private struct ReleaseArtifactFixture {
    let rootURL: URL
    let sourceURL: URL
    let scriptURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "InnoDI-ReleaseArtifactTests-\(UUID().uuidString)",
                isDirectory: true
            )
        sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
        scriptURL = packageRootURL()
            .appendingPathComponent("Tools/package-release-docc.sh")

        try FileManager.default.createDirectory(
            at: sourceURL.appendingPathComponent("nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("<html>InnoDI</html>\n".utf8).write(
            to: sourceURL.appendingPathComponent("index.html")
        )
        try Data("{\"schema\":2}\n".utf8).write(
            to: sourceURL.appendingPathComponent("nested/payload.json")
        )
    }

    func package(output: URL) throws {
        let result = try run(
            executable: scriptURL.path,
            arguments: [
                "--source", sourceURL.path,
                "--output", output.path,
            ]
        )
        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    func run(executable: String, arguments: [String]) throws -> ReleaseArtifactResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()

        return ReleaseArtifactResult(
            exitCode: process.terminationStatus,
            output: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }
}
