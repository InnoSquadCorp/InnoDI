import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("GenerateMock Macro Tests")
struct GenerateMockMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "GenerateMock": GenerateMockMacro.self,
    ]

    @Test("GenerateMock skips async/throws members and warns once")
    func generateMockWarnsOnUnsupportedAsyncThrowsMember() {
        assertMacroExpansionDiagnosticCodes(
            """
            @GenerateMock
            protocol UserService {
                func fetch(id: String) async throws -> String
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "mock.unsupported-member")
            ],
            macros: Self.macros
        )
    }

    @Test("GenerateMock attached to an empty protocol emits the experimental skeleton note")
    func generateMockEmitsSkeletonNoteForEmptyProtocol() {
        assertMacroExpansionDiagnosticCodes(
            """
            @GenerateMock
            protocol Marker {}
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

    @Test("GenerateMock synthesizes call-recording stubs for sync function and var requirements")
    func generateMockSynthesizesSyncMembers() throws {
        let source = """
        @GenerateMock
        protocol Greeter {
            var prefix: String { get set }
            func greet(name: String) -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse Greeter protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        guard let peer = peers.first?.description else {
            Issue.record("Expected one peer declaration for the mock")
            return
        }

        // Storage and method shape — just substring assertions because the
        // exact whitespace is defined by the generator.
        #expect(peer.contains("final class GreeterMock"))
        #expect(peer.contains("var prefix: String!"))
        #expect(peer.contains("private(set) var greetCalls"))
        #expect(peer.contains("var greetReturnValue: String?"))
        #expect(peer.contains("func greet(name: String) -> String"))
    }
}
