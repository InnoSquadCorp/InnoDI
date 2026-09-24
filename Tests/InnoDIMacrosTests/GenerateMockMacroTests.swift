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

    @Test("GenerateMock snapshots non-generic async-throwing shapes")
    func generateMockAsyncThrowingSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol AsyncService {
                func fetch(id: String) async throws -> String
                func refresh() async throws
            }
            """,
            matches: "asyncThrowingShapes",
            macros: Self.macros
        )
    }

    @Test("GenerateMock preserves typed throws and exposes preflight stub validation")
    func generateMockPreservesTypedThrows() throws {
        let source = """
        enum LoadFailure: Error { case unavailable }

        @GenerateMock
        protocol TypedAPI {
            func load(id: Int) async throws(LoadFailure) -> String
            func refresh() throws(LoadFailure)
        }
        """
        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(
            parsed.statements.compactMap {
                $0.item.as(ProtocolDeclSyntax.self)
            }.first
        )
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = try #require(peers.first?.description)

        #expect(context.diagnostics.isEmpty)
        #expect(peer.contains("var loadResult: Result<String, LoadFailure>?"))
        #expect(peer.contains("func load(id: Int) async throws(LoadFailure) -> String"))
        #expect(peer.contains("var refreshResult: Result<Void, LoadFailure>?"))
        #expect(peer.contains("var missingStubSelectors: [String]"))
        #expect(!peer.contains("Result<String, Error>"))
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
        #expect(peer.contains("private var __innodi_prefix_hba8821b572531e29IsStubbed = false"))
        #expect(peer.contains("var prefix: String {"))
        #expect(peer.contains("__innodi_prefix_hba8821b572531e29StubValue = newValue"))
        #expect(peer.contains("private(set) var greetCalls"))
        #expect(peer.contains("let generation: UInt64"))
        #expect(peer.contains("var greetReturnValue: String?"))
        #expect(peer.contains("!__innodi_greetIsStubbed ? \"greet\" : nil"))
        #expect(peer.contains("!__innodi_prefix_hba8821b572531e29IsStubbed ? \"prefix\" : nil"))
        #expect(peer.contains("var recordedCallCounts: [String: Int]"))
        #expect(peer.contains("\"greet\": greetCalls.count"))
        #expect(peer.contains("func greet(name: String) -> String"))
        #expect(peer.contains("enum InnoDIResetScope: Sendable"))
        #expect(peer.contains("func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot"))
        #expect(peer.contains("greetCalls.removeAll(keepingCapacity: false)"))
        #expect(peer.contains("__innodi_greetReturnValueStorage = nil"))
        #expect(peer.contains("was not set on \\(Self.self)"))
        #expect(!peer.contains("Swift.type(of: self)"))
    }

    @Test("GenerateMock emits empty dictionaries for property-only call snapshots")
    func generateMockPropertyOnlyResetSnapshotsUseEmptyDictionaries() throws {
        let source = """
        @GenerateMock
        protocol SettingsAPI {
            var title: String { get set }
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(parsed.statements.first?.item.as(ProtocolDeclSyntax.self))
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = try #require(peers.first?.description)

        #expect(context.diagnostics.isEmpty)
        #expect(peer.filter { !$0.isWhitespace }.contains("recordedCallCounts:[:]"))
    }

    @Test("GenerateMock uses lock-backed storage for Sendable protocols")
    func generateMockSupportsSendableInheritedProtocols() throws {
        let source = """
        @GenerateMock
        protocol SharedAPI: Sendable {
            func load() -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(parsed.statements.first?.item.as(ProtocolDeclSyntax.self))
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        let peer = try #require(peers.first?.description)
        #expect(context.diagnostics.isEmpty)
        #expect(peer.contains("struct LoadCall: Sendable"))
        #expect(peer.contains("InnoDITesting.DIConcurrentValueBox"))
        #expect(peer.contains("InnoDITesting.DIConcurrentMockState"))
        #expect(peer.contains("__innodiMockState.withCriticalRegion { generation in"))
        #expect(peer.contains("__innodi_loadCallsBox.replace(with: [])"))
        #expect(!peer.contains("@unchecked Sendable"))
    }

    @Test("GenerateMock covers every concurrency-safe storage effect")
    func generateMockSupportsConcurrentStorageEffects() throws {
        let source = """
        enum SharedFailure: Error { case unavailable }

        @GenerateMock
        protocol SharedAPI: Sendable {
            var title: String { get set }
            func load() throws(SharedFailure) -> String
            func fetch() throws -> String
            func refresh() throws
        }
        """
        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(
            parsed.statements.compactMap {
                $0.item.as(ProtocolDeclSyntax.self)
            }.first
        )
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = try #require(peers.first?.description)

        #expect(context.diagnostics.isEmpty)
        #expect(peer.contains("DIConcurrentValueBox<String?>(nil)"))
        #expect(peer.contains("DIConcurrentValueBox<Result<String, SharedFailure>?>(nil)"))
        #expect(peer.contains("DIConcurrentValueBox<Result<String, Error>>"))
        #expect(peer.contains("DIConcurrentValueBox<Error?>(nil)"))
        #expect(peer.contains("return __innodi_fetchResultBox.snapshot()"))
        #expect(peer.contains("if let error { throw error }"))
        #expect(peer.contains("!__innodi_loadStubbedBox.snapshot() ? \"load\" : nil"))
        #expect(peer.contains("!__innodi_fetchStubbedBox.snapshot() ? \"fetch\" : nil"))
        #expect(peer.contains("!__innodi_refreshStubbedBox.snapshot() ? \"refresh\" : nil"))
    }

    @Test("GenerateMock rejects unsupported concurrent and member-isolated shapes")
    func generateMockRejectsUnsupportedConcurrentShapes() throws {
        let cases = [
            """
            @GenerateMock
            protocol SharedAPI: Sendable {
                func transform<T>(_ value: T) -> T
            }
            """,
            """
            @GenerateMock
            protocol SharedAPI: Sendable {
                func update(_ value: inout Int)
            }
            """,
            """
            @GenerateMock
            protocol SharedAPI {
                @FeatureActor func load() -> String
            }
            """,
        ]

        for source in cases {
            let parsed = SwiftParser.Parser.parse(source: source)
            let decl = try #require(
                parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
            )
            let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
            let context = TestMacroExpansionContext()
            let peers = try GenerateMockMacro.expansion(
                of: attr,
                providingPeersOf: decl,
                in: context
            )
            #expect(peers.isEmpty)
            #expect(context.diagnostics.contains {
                $0.diagnosticID == MessageID(
                    domain: "InnoDI.validation",
                    id: "mock.unsupported-member"
                )
            })
        }
    }

    @Test("GenerateMock recognizes qualified Sendable inheritance")
    func generateMockSupportsQualifiedSendableInheritedProtocols() throws {
        let source = """
        @GenerateMock
        protocol SharedAPI: Swift.Sendable {
            func load() -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(parsed.statements.first?.item.as(ProtocolDeclSyntax.self))
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        let peer = try #require(peers.first?.description)
        #expect(context.diagnostics.isEmpty)
        #expect(peer.contains("InnoDITesting.DIConcurrentValueBox"))
    }

    @Test("GenerateMock fails closed for inherited protocol requirements")
    func generateMockRefusesInheritedProtocolRequirements() throws {
        let source = """
        protocol ParentAPI {
            func parentValue() -> String
        }

        @GenerateMock
        protocol ChildAPI: ParentAPI {
            func childValue() -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(
            parsed.statements.compactMap {
                $0.item.as(ProtocolDeclSyntax.self)
            }.last
        )
        let attr = try #require(
            decl.attributes.first?.as(AttributeSyntax.self)
        )

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.diagnosticID == MessageID(
                    domain: "InnoDI.validation",
                    id: "mock.unsupported-member"
                ) && $0.message.contains("ParentAPI inheritance")
            }
        )
    }

    @Test("GenerateMock permits an AnyObject class bound")
    func generateMockPermitsAnyObjectClassBound() throws {
        let source = """
        @GenerateMock
        protocol ClassBoundAPI: AnyObject {
            func load() -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(
            decl.attributes.first?.as(AttributeSyntax.self)
        )

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.count == 1)
        #expect(peers.first?.description.contains(
            "final class ClassBoundAPIMock: ClassBoundAPI"
        ) == true)
        #expect(context.diagnostics.isEmpty)
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

    @Test("GenerateMock disambiguates overloads whose normalized type stems collide")
    func generateMockDisambiguatesNormalizedOverloadStems() throws {
        let source = """
        @GenerateMock
        protocol API {
            func fetch(_ value: Int) -> String
            func fetch(_ value: [Int]) -> String
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(
            decl.attributes.first?.as(AttributeSyntax.self)
        )

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""
        let callProperties = peer.split(separator: "\n")
            .map(String.init)
            .filter {
                $0.contains("private(set) var fetchUnlabeledInt")
                    && $0.contains("Calls:")
            }

        #expect(callProperties.count == 2)
        #expect(Set(callProperties).count == 2)
        #expect(peer.contains("func fetch(_ value: Int) -> String"))
        #expect(peer.contains("func fetch(_ value: [Int]) -> String"))
    }

    @Test("GenerateMock disambiguates helpers from protocol property names")
    func generateMockDisambiguatesHelperAndPropertyNames() throws {
        let source = """
        @GenerateMock
        protocol API {
            var fetchCalls: Int { get set }
            func fetch()
        }
        """

        let parsed = SwiftParser.Parser.parse(source: source)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(
            decl.attributes.first?.as(AttributeSyntax.self)
        )

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = peers.first?.description ?? ""

        #expect(peer.contains("var fetchCalls: Int {"))
        #expect(!peer.contains("private(set) var fetchCalls:"))
        #expect(
            peer.split(separator: "\n").contains {
                $0.contains("private(set) var fetch")
                    && $0.contains("Calls:")
            }
        )
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

        #expect(peer.contains("private var __innodi_fetchIdStringResultStorage: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: \"fetchIdStringResult\"))"))
        #expect(peer.contains("private var __innodi_fetchPageIntResultStorage: Result<String, Error> = .failure(_InnoDIMockNotStubbed(selector: \"fetchPageIntResult\"))"))
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
        #expect(peer.contains("func transform(_ value1: Int, _ value2: String) -> String"))
        #expect(peer.contains("transformCalls.append(.init(generation: __innodiMockGeneration, value1: value1, value2: value2))"))
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
        #expect(peer.contains("applyCalls.append(.init(generation: __innodiMockGeneration, repeat: `repeat`))"))
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
        #expect(peer.contains("!__innodi_decodeUnlabeledTTypeIsStubbed ? \"decodeUnlabeledTType\" : nil"))
        #expect(peer.contains("guard let value = rawValue as? T"))
    }

    @Test("GenerateMock preflight covers every required stub category")
    func generateMockPreflightCoversRequiredStubs() throws {
        let parsed = SwiftParser.Parser.parse(source: """
        enum Failure: Error { case unavailable }

        @GenerateMock
        protocol CompleteAPI {
            var optionalValue: String? { get set }
            func value() -> String
            func fetch() throws -> String
            func refresh() throws
            func typed() throws(Failure) -> String
            func decode<T>(_ type: T.Type) -> T
        }
        """)
        let decl = try #require(
            parsed.statements.compactMap {
                $0.item.as(ProtocolDeclSyntax.self)
            }.first
        )
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )
        let peer = try #require(peers.first?.description)

        #expect(context.diagnostics.isEmpty)
        for selector in [
            "optionalValue", "value", "fetch", "refresh", "typed",
            "decodeUnlabeledTType",
        ] {
            #expect(peer.contains("? \"\(selector)\" : nil"))
        }
    }

    @Test("GenerateMock rejects generic typed throws and static properties")
    func generateMockRejectsUnsupportedMatrixAtAttribute() throws {
        let parsed = SwiftParser.Parser.parse(source: """
        enum Failure: Error { case unavailable }

        @GenerateMock
        protocol UnsupportedMatrix {
            static var shared: String { get }
            func decode<T>(_ type: T.Type) throws(Failure) -> T
        }
        """)
        let decl = try #require(
            parsed.statements.compactMap {
                $0.item.as(ProtocolDeclSyntax.self)
            }.first
        )
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(context.diagnostics.count == 1)
        let diagnostic = try #require(context.diagnostics.first)
        #expect(diagnostic.node.position == attr.position)
        #expect(diagnostic.message.contains("shared"))
        #expect(diagnostic.message.contains("decode"))
        #expect(
            diagnostic.diagnosticID == MessageID(
                domain: "InnoDI.validation",
                id: "mock.unsupported-member"
            )
        )
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

    @Test("GenerateMock preserves narrow protocol access without exporting public mocks")
    func generateMockPreservesNarrowProtocolAccess() throws {
        let cases = [
            ("private", "private final class PrivateAPIMock"),
            ("fileprivate", "fileprivate final class FileprivateAPIMock"),
            ("public", "final class PublicAPIMock"),
            ("package", "final class PackageAPIMock"),
        ]

        for (access, expectedDeclaration) in cases {
            let protocolName = access.capitalized + "API"
            let parsed = SwiftParser.Parser.parse(source: """
            @GenerateMock
            \(access) protocol \(protocolName) {
                func load() -> String
            }
            """)
            let decl = try #require(
                parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
            )
            let attr = try #require(
                decl.attributes.first?.as(AttributeSyntax.self)
            )

            let context = TestMacroExpansionContext()
            let peers = try GenerateMockMacro.expansion(
                of: attr,
                providingPeersOf: decl,
                in: context
            )
            let peer = try #require(peers.first?.description)

            #expect(peer.contains(expectedDeclaration))
            if access == "public" || access == "package" {
                #expect(!peer.contains("\(access) final class"))
            }
            #expect(context.diagnostics.isEmpty)
        }
    }

    @Test("GenerateMock preserves MainActor protocol isolation")
    func generateMockPreservesMainActorIsolation() throws {
        let parsed = SwiftParser.Parser.parse(source: """
            @MainActor
            @GenerateMock
            protocol IsolatedAPI {
                func load() -> String
            }
            """)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(
            decl.attributes.compactMap { $0.as(AttributeSyntax.self) }.first {
                $0.attributeName.trimmedDescription == "GenerateMock"
            }
        )

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(context.diagnostics.isEmpty)
        #expect(peers.first?.description.contains("@MainActor\nfinal class IsolatedAPIMock") == true)
        #expect(peers.first?.description.contains("private var __innodiMockGeneration: UInt64 = 0") == true)
        #expect(peers.first?.description.contains("func innoDIReset(_ scope: InnoDIResetScope)") == true)
    }

    @Test("GenerateMock fails closed for individually MainActor requirements")
    func generateMockRefusesIndividualMainActorIsolation() throws {
        let parsed = SwiftParser.Parser.parse(source: """
            @GenerateMock
            protocol PartlyIsolatedAPI {
                @MainActor func load() -> String
            }
            """)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(
                domain: "InnoDI.validation",
                id: "mock.unsupported-member"
            ) && $0.message.contains("load")
        })
    }

    @Test("GenerateMock rejects aggregate helper collisions")
    func generateMockRejectsAggregateHelperCollisions() throws {
        let sources = [
            """
            @GenerateMock
            protocol CollidingAPI {
                var recordedCallCounts: [String: Int] { get }
                func load() -> String
            }
            """,
            """
            enum Failure: Error { case missing }
            @GenerateMock
            protocol CollidingAPI {
                var missingStubSelectors: [String] { get }
                func load() throws(Failure) -> String
            }
            """,
            """
            @GenerateMock
            protocol CollidingAPI {
                func innoDIReset()
                func load() -> String
            }
            """,
            """
            @GenerateMock
            protocol CollidingAPI {
                var innoDICallHistoryGeneration: UInt64 { get }
                func load() -> String
            }
            """,
            """
            @GenerateMock
            protocol CollidingAPI {
                var innoDICallHistorySnapshot: Int { get }
                func load() -> String
            }
            """,
        ]
        for source in sources {
            let parsed = SwiftParser.Parser.parse(source: source)
            let decl = try #require(
                parsed.statements.compactMap {
                    $0.item.as(ProtocolDeclSyntax.self)
                }.first
            )
            let attr = try #require(decl.attributes.first?.as(AttributeSyntax.self))
            let context = TestMacroExpansionContext()
            let peers = try GenerateMockMacro.expansion(
                of: attr,
                providingPeersOf: decl,
                in: context
            )

            #expect(peers.isEmpty)
            #expect(context.diagnostics.contains {
                $0.message.contains("generated-helper collision")
            })
        }
    }

    @Test("GenerateMock fails closed for custom actor-isolated protocols")
    func generateMockRefusesCustomActorIsolation() throws {
        let parsed = SwiftParser.Parser.parse(source: """
            @FixtureActor
            @GenerateMock
            protocol IsolatedAPI {
                func load() -> String
            }
            """)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(
            decl.attributes.compactMap { $0.as(AttributeSyntax.self) }.first {
                $0.attributeName.trimmedDescription == "GenerateMock"
            }
        )
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(
                domain: "InnoDI.validation",
                id: "mock.unsupported-member"
            ) && $0.message.contains("isolation")
        })
    }

    @Test("GenerateMock fails closed for unsupported requirement modifiers")
    func generateMockRefusesUnsupportedRequirementModifiers() throws {
        let parsed = SwiftParser.Parser.parse(source: """
        @GenerateMock
        protocol IsolatedRequirementAPI {
            nonisolated func load() -> String
        }
        """)
        let decl = try #require(
            parsed.statements.first?.item.as(ProtocolDeclSyntax.self)
        )
        let attr = try #require(
            decl.attributes.first?.as(AttributeSyntax.self)
        )

        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attr,
            providingPeersOf: decl,
            in: context
        )

        #expect(peers.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.diagnosticID == MessageID(
                    domain: "InnoDI.validation",
                    id: "mock.unsupported-member"
                ) && $0.message.contains("load")
            }
        )
    }
}
