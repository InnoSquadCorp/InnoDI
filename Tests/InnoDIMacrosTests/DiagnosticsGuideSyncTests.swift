import Foundation
import Testing

@testable import InnoDIMacros

/// Enforces the sync contract stated at the top of `Diagnostics.swift`: every
/// `InnoDIDiagnosticCode` case must be described in the DocC
/// `DiagnosticsGuide` article. Before this test the contract was maintained
/// by convention only.
@Suite("Diagnostics guide sync")
struct DiagnosticsGuideSyncTests {
    @Test("Every diagnostic code is documented in the DocC DiagnosticsGuide")
    func everyDiagnosticCodeAppearsInGuide() throws {
        let guideURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("InnoDI", isDirectory: true)
            .appendingPathComponent("InnoDI.docc", isDirectory: true)
            .appendingPathComponent("DiagnosticsGuide.md")
        let guide = try String(contentsOf: guideURL, encoding: .utf8)

        let missing = InnoDIDiagnosticCode.allCases
            .map(\.rawValue)
            .filter { !guide.contains($0) }
            .sorted()

        #expect(
            missing.isEmpty,
            "Codes missing from DiagnosticsGuide.md: \(missing.joined(separator: ", "))"
        )
    }
}
