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

    @Test("GenerateMock synthesizes async-throwing stubs with a Result return slot")
    func generateMockSynthesizesAsyncThrowingMember() throws {
        let source = """
        @GenerateMock
        protocol UserService {
            func fetch(id: String) async throws -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse async-throws fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("func fetch(id: String) async throws -> String"))
        #expect(peer.contains("var fetchResult: Result<String, Error>"))
        #expect(peer.contains("try fetchResult.get()"))
        #expect(peer.contains("struct _InnoDIMockNotStubbed: Error"))
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
        #expect(!peer.contains("@unchecked Sendable"))
        #expect(peer.contains("private var __innodi_prefix_hba8821b572531e29StubValue: String?"))
        #expect(peer.contains("var prefix: String {"))
        #expect(peer.contains("__innodi_prefix_hba8821b572531e29StubValue = newValue"))
        #expect(peer.contains("private(set) var greetCalls"))
        #expect(peer.contains("var greetReturnValue: String?"))
        #expect(peer.contains("func greet(name: String) -> String"))
    }

    @Test("GenerateMock keeps property backing storage names unique after normalization")
    func generateMockKeepsPropertyBackingStorageNamesUnique() throws {
        let source = """
        @GenerateMock
        protocol CollidingProperties {
            var foo_bar: Int { get set }
            var fooBar: Int { get set }
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse colliding property fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("private var __innodi_fooBar_hd82736431662ffbdStubValue: Int?"))
        #expect(peer.contains("private var __innodi_fooBar_h9b9c617294f0c148StubValue: Int?"))
        #expect(peer.contains("var foo_bar: Int {"))
        #expect(peer.contains("var fooBar: Int {"))
    }

    @Test("GenerateMock qualifies helper names for overloaded methods")
    func generateMockQualifiesOverloadedMemberHelpers() throws {
        let source = """
        @GenerateMock
        protocol API {
            func fetch(id: String) -> String
            func fetch(page: Int) -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse overloaded API protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("struct FetchIdStringCall"))
        #expect(peer.contains("struct FetchPageIntCall"))
        #expect(peer.contains("var fetchIdStringReturnValue: String?"))
        #expect(peer.contains("var fetchPageIntReturnValue: String?"))
    }

    @Test("GenerateMock qualifies not-stubbed selectors for throwing overloads")
    func generateMockQualifiesNotStubbedSelectorsForThrowingOverloads() throws {
        let source = """
        @GenerateMock
        protocol ThrowingAPI {
            func fetch(id: String) throws -> String
            func fetch(page: Int) throws -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse throwing overloaded API protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("var fetchIdStringResult: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: \"fetchIdStringResult\"))"))
        #expect(peer.contains("var fetchPageIntResult: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: \"fetchPageIntResult\"))"))
    }

    @Test("GenerateMock keeps unnamed call-record fields unique")
    func generateMockKeepsUnnamedCallRecordFieldsUnique() throws {
        let source = """
        @GenerateMock
        protocol Transformer {
            func transform(_: Int, _: String) -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unnamed-parameter protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("let value1: Int"))
        #expect(peer.contains("let value2: String"))
        #expect(peer.contains("transformCalls.append(.init(value1: value1, value2: value2))"))
    }

    @Test("GenerateMock escapes keyword call-record fields")
    func generateMockEscapesKeywordCallRecordFields() throws {
        let source = """
        @GenerateMock
        protocol Keyworded {
            func apply(`repeat`: String) -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse keyword parameter protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("let `repeat`: String"))
        #expect(peer.contains("applyCalls.append(.init(repeat: `repeat`))"))
    }

    @Test("GenerateMock stores escaping closure arguments as property-safe function types")
    func generateMockStoresEscapingClosureArguments() throws {
        let source = """
        @GenerateMock
        protocol Observer {
            func observe(_ handler: @escaping @Sendable () -> Void)
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse escaping closure protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("let handler: @Sendable () -> Void"))
        #expect(peer.contains("func observe(_ handler: @escaping @Sendable () -> Void)"))
    }

    @Test("GenerateMock wraps optional return storage when the return type needs precedence")
    func generateMockWrapsOptionalReturnStorage() throws {
        let source = """
        protocol Event {}

        @GenerateMock
        protocol EventFactory {
            func makeEvent() -> any Event
            func makeHandler() -> () -> Void
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.compactMap({ $0.item.as(ProtocolDeclSyntax.self) }).first(where: {
            $0.name.text == "EventFactory"
        }),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse existential return protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("var makeEventReturnValue: (any Event)?"))
        #expect(peer.contains("var makeHandlerReturnValue: (() -> Void)?"))
    }

    @Test("GenerateMock treats explicit unit return as Void")
    func generateMockTreatsExplicitUnitReturnAsVoid() throws {
        let source = """
        @GenerateMock
        protocol Resettable {
            func reset() -> ()
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse explicit unit return protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("func reset()"))
        #expect(!peer.contains("resetReturnValue"))
    }

    @Test("GenerateMock supports generic methods with erased handlers")
    func generateMockSynthesizesGenericMethodHandlers() throws {
        let source = """
        @GenerateMock
        protocol Codec {
            func decode<T>(_ type: T.Type) -> T
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse generic Codec protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("func decode<T>(_ type: T.Type) -> T"))
        #expect(peer.contains("var decodeUnlabeledTTypeHandler: (([Any]) -> Any)?"))
        #expect(peer.contains("guard let value = rawValue as? T"))
    }

    @Test("GenerateMock refuses signatures it cannot lower without broken conformance")
    func generateMockRefusesUnsupportedSignatures() throws {
        let source = """
        struct TypedError: Error {}

        @GenerateMock
        protocol UnsupportedEffects {
            func update(_ value: inout Int)
            func perform(_ body: () throws -> Int) rethrows -> Int
            func load() throws(TypedError) -> String
            func make() -> some Sendable
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.compactMap({ $0.item.as(ProtocolDeclSyntax.self) }).first,
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unsupported effects protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "mock.unsupported-member")
            }
        )
    }

    @Test("GenerateMock refuses unsupported protocols without partial conformance")
    func generateMockRefusesUnsupportedProtocolsWithoutPartialConformance() throws {
        let source = """
        @GenerateMock
        protocol Repository {
            associatedtype Entity
            subscript(id: String) -> Entity { get }
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(ProtocolDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unsupported Repository protocol fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "mock.unsupported-member")
            }
        )
    }
}
