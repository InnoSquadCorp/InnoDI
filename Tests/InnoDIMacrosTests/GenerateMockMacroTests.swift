import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("GenerateMock Macro Tests")
struct GenerateMockMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "GenerateMock": GenerateMockMacro.self,
    ]

    @Test("GenerateMock attached to a protocol records the experimental skeleton note")
    func generateMockEmitsExperimentalNoteOnProtocol() {
        assertMacroExpansionDiagnosticCodes(
            """
            @GenerateMock
            protocol UserService {
                func fetch(id: String) async throws -> String
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "mock.experimental-skeleton")
            ],
            macros: Self.macros
        )
    }

    @Test("GenerateMock attached to a struct fails with mock.requires-protocol")
    func generateMockOnStructFailsWithProtocolRequirement() {
        assertMacroExpansionDiagnosticCodes(
            """
            @GenerateMock
            struct NotAProtocol {
                let id: String
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "mock.requires-protocol")
            ],
            macros: Self.macros
        )
    }
}
