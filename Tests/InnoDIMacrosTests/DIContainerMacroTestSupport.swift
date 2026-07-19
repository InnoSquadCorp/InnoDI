import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Shared declaration-matrix assertion used by the split container suites.
func assertUnsupportedContainerDeclaration(
    _ declaration: some DeclGroupSyntax,
    expectedID: String,
    expectedMessage: String
) throws {
    let attribute = try #require(
        declaration.attributes.first?.as(AttributeSyntax.self)
    )
    let context = TestMacroExpansionContext()

    let generated = try DIContainerMacro.expansion(
        of: attribute,
        providingMembersOf: declaration,
        in: context
    )

    #expect(generated.isEmpty)
    #expect(context.diagnostics.count == 1)
    #expect(
        context.diagnostics.first?.diagnosticID == MessageID(
            domain: "InnoDI.usage",
            id: expectedID
        )
    )
    #expect(context.diagnostics.first?.message == expectedMessage)
}

func assertExpandedSourceTypechecks(
    _ originalSource: String,
    macros: [String: any Macro.Type],
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) throws {
    let sourceLocation = Testing.SourceLocation(
        fileID: "\(fileID)",
        filePath: "\(filePath)",
        line: Int(line),
        column: Int(column)
    )

    let expansionResult = expandMacroSource(
        originalSource,
        macros: macros,
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth
    )

    if !expansionResult.diagnostics.isEmpty {
        let debug = expansionResult.diagnostics.map(\.debugDescription).joined(separator: "\n")
        Issue.record(
            Comment(rawValue: "Expected zero macro diagnostics before typechecking expanded source:\n\(debug)"),
            sourceLocation: sourceLocation
        )
        return
    }

    let fixtureDirectoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-Macro-Typecheck-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureDirectoryURL) }

    try FileManager.default.createDirectory(at: fixtureDirectoryURL, withIntermediateDirectories: true)

    let fixtureURL = fixtureDirectoryURL.appendingPathComponent(testFileName)
    let stdoutURL = fixtureDirectoryURL.appendingPathComponent("stdout.txt")
    let stderrURL = fixtureDirectoryURL.appendingPathComponent("stderr.txt")

    try expansionResult.expansion.write(to: fixtureURL, atomically: true, encoding: .utf8)
    FileManager.default.createFile(atPath: stdoutURL.path(percentEncoded: false), contents: Data())
    FileManager.default.createFile(atPath: stderrURL.path(percentEncoded: false), contents: Data())

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc", "-typecheck", fixtureURL.path(percentEncoded: false)]

    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    defer {
        stdoutHandle.closeFile()
        stderrHandle.closeFile()
    }
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle

    try process.run()
    process.waitUntilExit()

    let stdout = String(decoding: (try? Data(contentsOf: stdoutURL)) ?? Data(), as: UTF8.self)
    let stderr = String(decoding: (try? Data(contentsOf: stderrURL)) ?? Data(), as: UTF8.self)

    if process.terminationStatus != 0 {
        let message = """
            Expanded source failed to typecheck.
            Exit code: \(process.terminationStatus)
            stdout:
            \(stdout)
            stderr:
            \(stderr)

            Expanded source:
            \(expansionResult.expansion)
            """
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}
