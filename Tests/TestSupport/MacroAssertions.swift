import Foundation
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
@_spi(Testing) import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// Environment variable that, when set to "1", makes snapshot assertions record
/// the current macro expansion output to disk instead of comparing against it.
public let innoDISnapshotRecordEnvVar = "INNODI_RECORD_SNAPSHOTS"

public typealias DiagnosticSpec = SwiftSyntaxMacrosGenericTestSupport.DiagnosticSpec
public typealias NoteSpec = SwiftSyntaxMacrosGenericTestSupport.NoteSpec
public typealias FixItSpec = SwiftSyntaxMacrosGenericTestSupport.FixItSpec

// MARK: - Inline assertion

/// Asserts that expanding `originalSource` with the given macros produces
/// exactly `expectedExpandedSource` and that the emitted diagnostics match
/// `diagnostics`. Failures are routed through Swift Testing's `Issue.record`.
public func assertMacroExpansionInline(
    _ originalSource: String,
    expandedSource expectedExpandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: Macro.Type],
    applyFixIts: [String]? = nil,
    fixedSource expectedFixedSource: String? = nil,
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let specs = macros.mapValues { MacroSpec(type: $0) }
    SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
        originalSource,
        expandedSource: expectedExpandedSource,
        diagnostics: diagnostics,
        macroSpecs: specs,
        applyFixIts: applyFixIts,
        fixedSource: expectedFixedSource,
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth,
        failureHandler: recordFailure(_:),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}

// MARK: - Snapshot assertion

/// Asserts that expanding `originalSource` with the given macros produces an
/// expansion that matches the snapshot file `snapshot`.
///
/// Snapshot path: `<test file dir>/__Snapshots__/<test file base>/<snapshot>.swift`
///
/// When `INNODI_RECORD_SNAPSHOTS=1` is set, or no snapshot file exists yet, the
/// helper writes the current expansion to disk and reports an Issue so the run
/// does not silently pass on first record.
public func assertMacroExpansionSnapshot(
    _ originalSource: String,
    matches snapshot: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: Macro.Type],
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let sourceLocation = Testing.SourceLocation(
        fileID: "\(fileID)",
        filePath: "\(filePath)",
        line: Int(line),
        column: Int(column)
    )

    let expansionResult = expand(
        originalSource,
        macros: macros,
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth
    )
    let expansion = expansionResult.expansion
    let contextDiagnostics = expansionResult.diagnostics

    if contextDiagnostics.count != diagnostics.count {
        let debug = contextDiagnostics.map(\.debugDescription).joined(separator: "\n")
        let message = """
            Expected \(diagnostics.count) diagnostics but received \(contextDiagnostics.count):
            \(debug)
            """
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    } else {
        let expansionContext = DiagnosticAssertionContext.macroExpansion(expansionResult.context)

        for (actual, expected) in zip(contextDiagnostics, diagnostics) {
            assertDiagnostic(
                actual,
                in: expansionContext,
                expected: expected,
                failureHandler: recordFailure(_:)
            )
        }
    }

    let snapshotURL = snapshotFileURL(for: snapshot, callerFilePath: "\(filePath)")
    let recordMode = ProcessInfo.processInfo.environment[innoDISnapshotRecordEnvVar] == "1"
    let fileExists = FileManager.default.fileExists(atPath: snapshotURL.path)

    if recordMode || !fileExists {
        do {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try expansion.write(to: snapshotURL, atomically: true, encoding: String.Encoding.utf8)
            let message = "Recorded snapshot at \(snapshotURL.path). Re-run tests to verify."
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        } catch {
            let message = "Failed to write snapshot at \(snapshotURL.path): \(error)"
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        }
        return
    }

    do {
        let expected = try String(contentsOf: snapshotURL, encoding: String.Encoding.utf8)
        let actualTrimmed = trimBlankBoundaries(expansion)
        let expectedTrimmed = trimBlankBoundaries(expected)
        if actualTrimmed != expectedTrimmed {
            let message = """
                Macro expansion did not match snapshot \(snapshotURL.lastPathComponent).

                --- Expected (snapshot)
                \(expected)
                --- Actual (expansion)
                \(expansion)
                ---

                To update, re-run with \(innoDISnapshotRecordEnvVar)=1.
                """
            Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
        }
    } catch {
        let message = "Failed to read snapshot at \(snapshotURL.path): \(error)"
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}

// MARK: - Diagnostic-code assertion

/// Asserts that expanding `originalSource` with the given macros produces a
/// diagnostic set whose `MessageID`s exactly match `expectedCodes` (as a
/// multiset — duplicates are significant, order is not).
///
/// Prefer this over message-substring matching: it binds tests to the stable
/// `InnoDIDiagnosticCode` raw values instead of the English wording. When the
/// check fails, the failure message prints the full debug description of every
/// observed diagnostic so the expected list can be corrected.
public func assertMacroExpansionDiagnosticCodes(
    _ originalSource: String,
    expectedCodes: [MessageID],
    macros: [String: Macro.Type],
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    let sourceLocation = Testing.SourceLocation(
        fileID: "\(fileID)",
        filePath: "\(filePath)",
        line: Int(line),
        column: Int(column)
    )

    let expansionResult = expand(
        originalSource,
        macros: macros,
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth
    )
    let contextDiagnostics = expansionResult.diagnostics

    let observed = contextDiagnostics.map { $0.diagnosticID }
    let expectedCounts = frequencyMap(expectedCodes)
    let observedCounts = frequencyMap(observed)

    if expectedCounts != observedCounts {
        let debug = contextDiagnostics.map(\.debugDescription).joined(separator: "\n")
        let expectedList = expectedCodes.map(describe).joined(separator: ", ")
        let observedList = observed.map(describe).joined(separator: ", ")
        let message = """
            Expected diagnostic codes did not match.
            Expected: [\(expectedList)]
            Observed: [\(observedList)]
            Full diagnostics:
            \(debug)
            """
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}

private func frequencyMap(_ ids: [MessageID]) -> [String: Int] {
    var map: [String: Int] = [:]
    for id in ids {
        map[describe(id), default: 0] += 1
    }
    return map
}

private func describe(_ id: MessageID) -> String {
    // MessageID's stored properties are private; use its reflected debug-style
    // representation, which is formatted as `<domain>/<id>`.
    String(reflecting: id)
}

// MARK: - Internals

private func expand(
    _ originalSource: String,
    macros: [String: Macro.Type],
    testModuleName: String,
    testFileName: String,
    indentationWidth: Trivia
) -> (
    expansion: String,
    diagnostics: [SwiftDiagnostics.Diagnostic],
    context: BasicMacroExpansionContext
) {
    let specs = macros.mapValues { MacroSpec(type: $0) }
    let origSourceFile = Parser.parse(source: originalSource)
    let context = BasicMacroExpansionContext(
        sourceFiles: [origSourceFile: .init(moduleName: testModuleName, fullFilePath: testFileName)]
    )
    let expandedSourceFile = origSourceFile.expand(
        macroSpecs: specs,
        contextGenerator: { syntax in
            BasicMacroExpansionContext(sharingWith: context, lexicalContext: syntax.allMacroLexicalContexts())
        },
        indentationWidth: indentationWidth
    )
    return (expandedSourceFile.description, context.diagnostics, context)
}

private func snapshotFileURL(for snapshot: String, callerFilePath: String) -> URL {
    let callerURL = URL(fileURLWithPath: callerFilePath)
    let testFileBase = callerURL.deletingPathExtension().lastPathComponent
    let testDir = callerURL.deletingLastPathComponent()
    return testDir
        .appendingPathComponent("__Snapshots__", isDirectory: true)
        .appendingPathComponent(testFileBase, isDirectory: true)
        .appendingPathComponent("\(snapshot).swift", isDirectory: false)
}

private func trimBlankBoundaries(_ source: String) -> String {
    var scalars = Substring(source)
    while let first = scalars.first, first.isNewline { scalars = scalars.dropFirst() }
    while let last = scalars.last, last.isNewline { scalars = scalars.dropLast() }
    return String(scalars)
}

private func recordFailure(_ spec: SwiftSyntaxMacrosGenericTestSupport.TestFailureSpec) {
    let location = Testing.SourceLocation(
        fileID: spec.location.fileID,
        filePath: spec.location.filePath,
        line: spec.location.line,
        column: spec.location.column
    )
    Issue.record(Comment(rawValue: spec.message), sourceLocation: location)
}
