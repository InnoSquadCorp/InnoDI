import Foundation
import Testing

@Suite("Macro fatalError guard script contracts")
struct MacroFatalErrorGuardScriptTests {
    @Test("Fallback scanner succeeds when ripgrep is unavailable")
    func fallbackScannerAcceptsCleanSources() throws {
        let fixture = try MacroFatalErrorGuardFixture(
            source: "func expand() -> String { \"expanded\" }\n"
        )
        defer { fixture.remove() }

        let result = try fixture.runWithoutRipgrep()

        #expect(result.exitCode == 0, Comment(rawValue: result.output))
        #expect(result.output.contains("No fatalError calls found"))
    }

    @Test("Fallback scanner rejects fatalError calls")
    func fallbackScannerRejectsFatalError() throws {
        let fixture = try MacroFatalErrorGuardFixture(
            source: "func expand() -> Never { fatalError(\"unexpected\") }\n"
        )
        defer { fixture.remove() }

        let result = try fixture.runWithoutRipgrep()

        #expect(result.exitCode == 1, Comment(rawValue: result.output))
        #expect(result.output.contains("Unexpected fatalError call(s)"))
        #expect(result.output.contains("Fixture.swift:1"))
    }
}

private struct MacroFatalErrorGuardResult {
    let exitCode: Int32
    let output: String
}

private struct MacroFatalErrorGuardFixture {
    let rootURL: URL

    init(source: String) throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "InnoDI-MacroFatalErrorGuard-\(UUID().uuidString)",
            isDirectory: true
        )
        let macrosURL = rootURL.appendingPathComponent(
            "Sources/InnoDIMacros",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: macrosURL,
            withIntermediateDirectories: true
        )
        try source.write(
            to: macrosURL.appendingPathComponent("Fixture.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    func runWithoutRipgrep() throws -> MacroFatalErrorGuardResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            packageRootURL()
                .appendingPathComponent("Tools/check-no-fatalerror-in-macros.sh")
                .path,
            "--root",
            rootURL.path,
        ]
        process.standardOutput = output
        process.standardError = output

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin"
        process.environment = environment

        try process.run()
        process.waitUntilExit()

        return MacroFatalErrorGuardResult(
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
