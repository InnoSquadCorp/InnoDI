import Foundation
import Testing

@testable import InnoDIDependencyGraphCLI

@Suite("Graphviz executable resolution")
struct GraphvizResolutionTests {
    @Test("dot resolution searches PATH directly")
    func dotResolutionSearchesPathDirectly() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-dot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dotURL = directory.appendingPathComponent("dot")
        try "#!/bin/sh\nexit 0\n".write(to: dotURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: dotURL.path(percentEncoded: false)
        )

        #expect(resolveDotExecutable(environment: ["PATH": directory.path(percentEncoded: false)]) == dotURL.path(percentEncoded: false))
    }

    @Test("dot resolution prefers INNODI_GRAPHVIZ_DOT over PATH")
    func dotResolutionPrefersEnvironmentOverride() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-dot-override-\(UUID().uuidString)", isDirectory: true)
        let pathDirectory = directory.appendingPathComponent("path", isDirectory: true)
        let overrideDirectory = directory.appendingPathComponent("override", isDirectory: true)
        try FileManager.default.createDirectory(at: pathDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: overrideDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pathDotURL = pathDirectory.appendingPathComponent("dot")
        let overrideDotURL = overrideDirectory.appendingPathComponent("custom-dot")
        for executableURL in [pathDotURL, overrideDotURL] {
            try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: executableURL.path(percentEncoded: false)
            )
        }

        #expect(
            resolveDotExecutable(
                environment: [
                    "INNODI_GRAPHVIZ_DOT": overrideDotURL.path(percentEncoded: false),
                    "PATH": pathDirectory.path(percentEncoded: false)
                ]
            ) == overrideDotURL.path(percentEncoded: false)
        )
    }

    @Test("process capture drains stdout and stderr without deadlock", .timeLimit(.minutes(1)))
    func processCaptureDrainsStdoutAndStderrWithoutDeadlock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("innodi-process-capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let executableURL = directory.appendingPathComponent("fake-dot")
        let chunk = String(repeating: "0123456789abcdef", count: 8)
        let script = """
        #!/bin/sh
        i=0
        while [ "$i" -lt 5000 ]; do
          printf 'stdout-%04d-\(chunk)\\n' "$i"
          printf 'stderr-%04d-\(chunk)\\n' "$i" >&2
          i=$((i + 1))
        done
        exit 0
        """
        try script.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path(percentEncoded: false)
        )

        let outputURL = directory.appendingPathComponent("graph.png")
        let exitCode = writeDOTAsPNG(
            dotContent: "digraph InnoDI {}\n",
            outputPath: outputURL.path(percentEncoded: false),
            environment: [
                "INNODI_GRAPHVIZ_DOT": executableURL.path(percentEncoded: false),
                "PATH": "",
            ]
        )

        #expect(exitCode == ExitCode.success)
    }
}
