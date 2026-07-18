import Foundation
import Testing

@Suite("Macro expansion dump script contracts")
struct MacroExpansionDumpScriptTests {
    @Test("Compiler expansion blocks become one reviewable Swift artifact")
    func successfulExtraction() throws {
        let fixture = try MacroExpansionDumpFixture(mode: .success)
        defer { fixture.remove() }

        let result = try fixture.run(arguments: [
            "--target", "Consumer",
            "--output", fixture.outputURL.path,
        ])

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("Wrote 2 macro expansion(s)"))
        let artifact = try String(
            contentsOf: fixture.outputURL,
            encoding: .utf8
        )
        #expect(artifact.contains("// Swift version 6.3 (fake)"))
        #expect(artifact.contains("// MARK: - @__swiftmacro_Test_One.swift"))
        #expect(artifact.contains("struct GeneratedOne {}"))
        #expect(artifact.contains("// MARK: - @__swiftmacro_Test_Two.swift"))
        #expect(artifact.contains("extension GeneratedTwo {}"))
        #expect(!artifact.contains("[1/1] Build complete"))

        let arguments = try String(
            contentsOf: fixture.argumentsURL,
            encoding: .utf8
        )
        #expect(arguments.contains("build\n"))
        #expect(arguments.contains("--package-path\n"))
        #expect(arguments.contains("/\(fixture.rootURL.lastPathComponent)\n"))
        #expect(arguments.contains("--scratch-path\n"))
        #expect(arguments.contains("--target\nConsumer\n"))
        #expect(arguments.contains("-Xswiftc\n-Xfrontend\n"))
        #expect(arguments.contains("-Xswiftc\n-dump-macro-expansions\n"))
    }

    @Test("A successful build without expansions fails closed")
    func missingExpansionsFail() throws {
        let fixture = try MacroExpansionDumpFixture(mode: .noExpansions)
        defer { fixture.remove() }

        let result = try fixture.run(arguments: [
            "--output", fixture.outputURL.path,
        ])

        #expect(result.exitCode == 1)
        #expect(result.output.contains("compiler emitted no macro expansions"))
        #expect(!FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    @Test("Build failures surface compiler output and create no artifact")
    func buildFailureIsPreserved() throws {
        let fixture = try MacroExpansionDumpFixture(mode: .buildFailure)
        defer { fixture.remove() }

        let result = try fixture.run(arguments: [
            "--output", fixture.outputURL.path,
        ])

        #expect(result.exitCode == 1)
        #expect(result.output.contains("consumer build failed"))
        #expect(result.output.contains("error: synthetic compiler failure"))
        #expect(!FileManager.default.fileExists(atPath: fixture.outputURL.path))
    }

    @Test("Output inside a build target is rejected before invoking Swift")
    func sourceOutputIsRejected() throws {
        let fixture = try MacroExpansionDumpFixture(mode: .success)
        defer { fixture.remove() }
        let unsafeOutput = fixture.rootURL
            .appendingPathComponent("Sources/Consumer/Generated.swift")

        let result = try fixture.run(arguments: [
            "--output", unsafeOutput.path,
        ])

        #expect(result.exitCode == 2)
        #expect(result.output.contains("must stay outside consumer Sources/ and Tests/"))
        #expect(!FileManager.default.fileExists(atPath: fixture.argumentsURL.path))
    }
}

private struct MacroExpansionDumpResult {
    let exitCode: Int32
    let output: String
}

private struct MacroExpansionDumpFixture {
    enum Mode: String {
        case success
        case noExpansions
        case buildFailure
    }

    let rootURL: URL
    let fakeSwiftURL: URL
    let argumentsURL: URL
    let outputURL: URL
    let mode: Mode

    init(mode: Mode) throws {
        self.mode = mode
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MacroExpansionDump-\(UUID().uuidString)",
            isDirectory: true
        )
        fakeSwiftURL = rootURL.appendingPathComponent("fake-swift")
        argumentsURL = rootURL.appendingPathComponent("swift-arguments.txt")
        outputURL = rootURL.appendingPathComponent("build/expansions.swift")

        try FileManager.default.createDirectory(
            at: rootURL.appendingPathComponent("Sources/Consumer"),
            withIntermediateDirectories: true
        )
        try "// fixture\n".write(
            to: rootURL.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        if [[ "${1:-}" == "--version" ]]; then
            echo "Swift version 6.3 (fake)"
            exit 0
        fi
        printf '%s\\n' "$@" > "${INNODI_FAKE_SWIFT_ARGUMENTS_PATH:?}"
        case "${INNODI_FAKE_SWIFT_MODE:?}" in
            success)
                cat <<'OUTPUT'
        [1/1] Build complete
        @__swiftmacro_Test_One.swift
        ------------------------------
        struct GeneratedOne {}
        ------------------------------
        warning: unrelated build warning
        @__swiftmacro_Test_Two.swift
        ------------------------------
        extension GeneratedTwo {}
        ------------------------------
        OUTPUT
                ;;
            noExpansions)
                echo "[1/1] Build complete"
                ;;
            buildFailure)
                echo "error: synthetic compiler failure"
                exit 1
                ;;
        esac
        """.write(to: fakeSwiftURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeSwiftURL.path
        )
    }

    func run(arguments: [String]) throws -> MacroExpansionDumpResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            packageRootURL()
                .appendingPathComponent("Tools/dump-macro-expansions.sh")
                .path,
            "--package-path", rootURL.path,
        ] + arguments
        process.standardOutput = output
        process.standardError = output

        var environment = ProcessInfo.processInfo.environment
        environment["INNODI_SWIFT_EXECUTABLE"] = fakeSwiftURL.path
        environment["INNODI_FAKE_SWIFT_ARGUMENTS_PATH"] = argumentsURL.path
        environment["INNODI_FAKE_SWIFT_MODE"] = mode.rawValue
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        return MacroExpansionDumpResult(
            exitCode: process.terminationStatus,
            output: String(
                decoding: output.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
