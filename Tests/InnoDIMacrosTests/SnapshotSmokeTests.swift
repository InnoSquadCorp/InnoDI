import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Macro snapshot helper smoke")
struct SnapshotSmokeTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
    ]

    @Test("Input-only container expands to expected init shape")
    func inputOnlyContainerSnapshot() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var baseURL: String
            }
            """

        assertMacroExpansionSnapshot(
            source,
            matches: "inputOnlyContainer",
            macros: Self.macros
        )
    }

    @Test("Missing shared factory reports a diagnostic inline")
    func sharedFactoryRequiredDiagnosticInline() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.shared)
                var apiClient: any APIClientProtocol
            }
            """

        assertMacroExpansionInline(
            source,
            expandedSource: """
                struct AppContainer {
                    @InnoDI._InnoDIProvideAccessor(recovery: true)
                    var apiClient: any APIClientProtocol
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Provide(.shared) requires factory: <expr>, type: Type.self, or property initializer.",
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Snapshot helper validates diagnostics when requested")
    func sharedFactoryRequiredDiagnosticSnapshot() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.shared)
                var apiClient: any APIClientProtocol
            }
            """

        assertMacroExpansionSnapshot(
            source,
            matches: "sharedFactoryRequiredDiagnostic",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "provide.shared-factory-required"),
                    message: "@Provide(.shared) requires factory: <expr>, type: Type.self, or property initializer.",
                    line: 3,
                    column: 5
                )
            ],
            macros: Self.macros
        )
    }
}

/// Directly exercises the `SnapshotStorage` helpers that back both
/// `assertMacroExpansionSnapshot` and `assertTextSnapshot`. These tests
/// confirm that record-mode is actually wired to the env var and that
/// snapshot file I/O round-trips — previously the only coverage for this
/// code path was the implicit "first-record" behaviour inside the macro
/// and CLI suites.
///
/// All tests write into `FileManager.default.temporaryDirectory` and clean
/// up in `defer`, so the real `__Snapshots__` tree is never touched.
///
/// Record-mode detection is exercised through the injectable `environment`
/// parameter rather than `setenv`: mutating the process environment here
/// would race the parallel snapshot suites that consult
/// `isSnapshotRecordModeEnabled()` at runtime.
@Suite("Snapshot storage helpers")
struct SnapshotStorageTests {
    @Test("Record-mode detection follows the env var")
    func recordModeTogglesWithEnvVar() throws {
        #expect(isSnapshotRecordModeEnabled(
            environment: [innoDISnapshotRecordEnvVar: "1"]
        ))
        #expect(!isSnapshotRecordModeEnabled(
            environment: [innoDISnapshotRecordEnvVar: "0"]
        ))
        #expect(!isSnapshotRecordModeEnabled(environment: [:]))
    }

    @Test("writeSnapshot creates intermediate directories and roundtrips through readSnapshot")
    func writeAndReadRoundtrip() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        // Force a fake caller file deep inside a nested tmp tree so
        // `snapshotFileURL` has to create `__Snapshots__/<base>/` from scratch.
        let fakeCaller = tempRoot
            .appendingPathComponent("Nested", isDirectory: true)
            .appendingPathComponent("FakeTests.swift")

        let url = snapshotFileURL(
            for: "roundtripCase",
            callerFilePath: fakeCaller.path,
            fileExtension: ".txt"
        )
        #expect(url.lastPathComponent == "roundtripCase.txt")
        #expect(url.path.contains("/__Snapshots__/FakeTests/"))
        #expect(!FileManager.default.fileExists(atPath: url.path))

        let payload = "alpha\nbeta\ngamma\n"
        try writeSnapshot(payload, to: url)

        #expect(FileManager.default.fileExists(atPath: url.path))
        let readBack = try readSnapshot(at: url)
        #expect(readBack == payload)
    }

    @Test("writeSnapshot overwrites an existing snapshot file")
    func writeOverwritesExistingFile() throws {
        let tempRoot = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let fakeCaller = tempRoot.appendingPathComponent("OverwriteTests.swift")
        let url = snapshotFileURL(
            for: "overwriteCase",
            callerFilePath: fakeCaller.path,
            fileExtension: ".txt"
        )

        try writeSnapshot("old contents", to: url)
        try writeSnapshot("new contents", to: url)

        #expect(try readSnapshot(at: url) == "new contents")
    }

    @Test("trimBlankBoundaries strips surrounding newlines but preserves interior blank lines")
    func trimBlankBoundariesBehavior() {
        #expect(trimBlankBoundaries("\n\nhello\n\n") == "hello")
        #expect(trimBlankBoundaries("hello\nworld") == "hello\nworld")
        // Interior blank lines must be preserved — they are meaningful in
        // both Swift expansion output and CLI stdout.
        #expect(trimBlankBoundaries("\nhello\n\nworld\n") == "hello\n\nworld")
        // Pure-newline input collapses to empty.
        #expect(trimBlankBoundaries("\n\n\n") == "")
    }
}

// MARK: - helpers

private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-SnapshotStorageTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
