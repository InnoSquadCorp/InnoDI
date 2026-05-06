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

    @Test("Missing concrete opt-in reports a diagnostic with a Fix-It")
    func concreteOptInDiagnosticInline() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """

        assertMacroExpansionInline(
            source,
            expandedSource: """
                struct AppContainer {
                    var apiClient: APIClient {
                        get {
                            return _storage_apiClient
                        }
                    }

                    private let _storage_apiClient: APIClient
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Concrete dependency 'apiClient: APIClient' requires concrete: true.",
                    line: 3,
                    column: 5,
                    notes: [
                        NoteSpec(
                            message: "InnoDI defaults to protocol-typed storage so container diffs stay reviewable and the graph stays substitutable. If this dependency must remain a concrete type, opt in explicitly with concrete: true; apply the fixit named 'Add concrete: true' to insert the argument.",
                            line: 3,
                            column: 5
                        ),
                        NoteSpec(
                            message: "If protocol-first wiring is possible, prefer changing the property type to an existential such as any Protocol.",
                            line: 4,
                            column: 9
                        ),
                    ],
                    fixIts: [FixItSpec(message: "Add concrete: true")]
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Snapshot helper validates diagnostics when requested")
    func concreteOptInDiagnosticSnapshot() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """

        assertMacroExpansionSnapshot(
            source,
            matches: "concreteOptInDiagnosticSnapshot",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required"),
                    message: "Concrete dependency 'apiClient: APIClient' requires concrete: true.",
                    line: 3,
                    column: 5,
                    notes: [
                        NoteSpec(
                            message: "InnoDI defaults to protocol-typed storage so container diffs stay reviewable and the graph stays substitutable. If this dependency must remain a concrete type, opt in explicitly with concrete: true; apply the fixit named 'Add concrete: true' to insert the argument.",
                            line: 3,
                            column: 5
                        ),
                        NoteSpec(
                            message: "If protocol-first wiring is possible, prefer changing the property type to an existential such as any Protocol.",
                            line: 4,
                            column: 9
                        ),
                    ],
                    fixIts: [FixItSpec(message: "Add concrete: true")]
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
/// This suite runs serialized because `isSnapshotRecordModeEnabled()` reads a
/// process-global environment variable that other snapshot tests also consult
/// at runtime.
@Suite("Snapshot storage helpers", .serialized)
struct SnapshotStorageTests {
    @Test("Record-mode detection follows the env var")
    func recordModeTogglesWithEnvVar() throws {
        let original = ProcessInfo.processInfo.environment[innoDISnapshotRecordEnvVar]
        defer { restoreEnvVar(innoDISnapshotRecordEnvVar, to: original) }

        setenv(innoDISnapshotRecordEnvVar, "1", 1)
        #expect(isSnapshotRecordModeEnabled())

        setenv(innoDISnapshotRecordEnvVar, "0", 1)
        #expect(!isSnapshotRecordModeEnabled())

        unsetenv(innoDISnapshotRecordEnvVar)
        #expect(!isSnapshotRecordModeEnabled())
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

private func restoreEnvVar(_ name: String, to value: String?) {
    if let value {
        setenv(name, value, 1)
    } else {
        unsetenv(name)
    }
}
