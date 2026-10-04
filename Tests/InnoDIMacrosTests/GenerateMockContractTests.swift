import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("GenerateMock recording contracts")
struct GenerateMockContractTests {
    @Test("Nonescaping closures fail at the attribute before an invalid peer is emitted", arguments: [
        "func call(_ callback: () -> Void)",
        "func call(_ callback: @Sendable () -> Void)",
        "func call(_ callback: @autoclosure () -> Bool)",
        "func call(_ callback: ((Int) -> Bool))",
        "func call<T>(_ callback: (T) -> Void, value: T)",
    ])
    func rejectsNonescapingRecording(_ requirement: String) throws {
        let (peer, diagnostics) = try expand(requirement)
        #expect(peer.isEmpty)
        let diagnostic = try #require(diagnostics.first)
        #expect(diagnostic.diagnosticID == MessageID(domain: "InnoDI.validation", id: "mock.unsupported-member"))
        #expect(diagnostic.message.contains("nonescaping closure parameter 'callback' cannot be retained"))
        #expect(diagnostic.node.is(AttributeSyntax.self))
    }

    @Test("Retained closures preserve their laziness and function type")
    func preservesEscapingClosures() throws {
        let (peer, diagnostics) = try expand("""
            func lazy(_ condition: @autoclosure @escaping () -> Bool)
            func optional(_ callback: (() -> Int)?)
            func many(_ callbacks: (() -> Void)...)
            func pointer(_ callback: @convention(c) () -> Int32)
            """)
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("let condition: () -> Bool"))
        #expect(peer.contains("condition: condition)"))
        #expect(!peer.contains("condition: condition()"))
        #expect(peer.contains("let callback: (() -> Int)?"))
        #expect(peer.contains("let callbacks: [(() -> Void)]"))
        #expect(peer.contains("let callback: @convention(c) () -> Int32"))
    }

    @Test("Variadic requirements retain array arguments and the original call syntax")
    func recordsVariadics() throws {
        let (peer, diagnostics) = try expand("func sum(_ values: Int...) -> Int")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("let values: [Int]"))
        #expect(peer.contains("func sum(_ values: Int...) -> Int"))
    }

    @Test("Copyable ownership arguments use explicit copies in retained records and erased handlers")
    func preservesCopyableOwnership() throws {
        let (peer, diagnostics) = try expand("""
            func consume(_ value: consuming String)
            func borrow(_ value: borrowing String)
            func send(_ value: sending String)
            func echo<T>(_ value: consuming T) -> T
            """)
        #expect(diagnostics.isEmpty)
        #expect(!peer.contains("let value: consuming"))
        #expect(!peer.contains("let value: borrowing"))
        #expect(!peer.contains("let value: sending"))
        #expect(peer.contains("value: copy value"))
        #expect(peer.contains("handler([copy value])"))
    }

    @Test("Sendable record storage captures immutable ownership copies")
    func capturesOwnershipBeforeLocking() throws {
        let (peer, diagnostics) = try expand("func own(_ value: consuming String)", inheritance: ": Sendable")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("let __innodiValueCopy = copy value"))
        #expect(peer.contains("generation: generation, value: __innodiValueCopy"))
    }

    @Test("Unsupported transfer and lifetime promises get an actionable reason", arguments: [
        ("func load() -> sending String", "sending results"),
        ("func load<T>() -> sending T", "sending results"),
        ("func record<T: ~Copyable>(_ value: borrowing T)", "noncopyable or nonescapable"),
        ("func update(_ value: inout Int)", "inout parameter 'value'"),
    ])
    func rejectsUnsupportedLifetimes(_ requirement: String, reason: String) throws {
        let (peer, diagnostics) = try expand(requirement)
        #expect(peer.isEmpty)
        #expect(diagnostics.count == 1)
        #expect(diagnostics.first?.message.contains(reason) == true)
    }

    @Test("Call metadata and input fields have separate, unambiguous names")
    func reservesGeneration() throws {
        let (peer, diagnostics) = try expand("func accept(generation: Int, generation2: Int, _ _: Int, value3: Int)")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("let generation: UInt64"))
        #expect(peer.contains("let generation3: Int"))
        #expect(peer.contains("let generation2: Int"))
        #expect(peer.contains("let value32: Int"))
        #expect(peer.contains("let value3: Int"))
        #expect(peer.contains("generation3: generation, generation2: generation2"))
    }

    @Test("The generation closure does not capture a same-spelled caller argument")
    func reservesConcurrentGeneration() throws {
        let (peer, diagnostics) = try expand("func accept(generation: UInt64)", inheritance: ": Sendable")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("withCriticalRegion { generation2 in"))
        #expect(peer.contains("generation: generation2, generation2: generation"))
    }

    @Test("A valid erased handler receives caller arguments despite local-name collisions")
    func preservesHandlerArguments() throws {
        let (peer, diagnostics) = try expand("func echo<T>(_ handler: T, handler2: Int, rawValue: Int, value: Int) -> T")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("guard let handler3 ="))
        #expect(peer.contains("let rawValue2 = handler3([handler, handler2, rawValue, value])"))
        #expect(peer.contains("guard let value2 = rawValue2 as? T"))
        #expect(peer.contains("return value2"))
    }

    @Test("Caller argument names do not hide generated instance storage")
    func qualifiesShadowedStorage() throws {
        let (peer, diagnostics) = try expand("func load(loadCalls: Int, __innodiMockGeneration: Int)")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("self.loadCalls.append(.init(generation: self.__innodiMockGeneration"))
    }

    @Test("Private state and function helpers avoid protocol requirement names")
    func allocatesHelpers() throws {
        let (peer, diagnostics) = try expand("""
            var __innodiMockGeneration: Int { get }
            func load()
            func loadCalls()
            """)
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("private var __innodiMockGeneration2: UInt64"))
        #expect(peer.contains("func loadCalls()"))
        #expect(!peer.contains("var loadCalls:"))
    }

    @Test("Separate type and value namespaces remain supported")
    func preservesTypeValueNames() throws {
        let (peer, diagnostics) = try expand("""
            var LoadCall: Int { get }
            var InnoDIResetScope: Int { get }
            func load()
            """)
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("struct LoadCall"))
        #expect(peer.contains("var LoadCall: Int"))
        #expect(peer.contains("enum InnoDIResetScope"))
        #expect(peer.contains("var InnoDIResetScope: Int"))
    }

    @Test("Functions with arguments keep compatible same-named recording helpers")
    func preservesLabeledMethodOverloads() throws {
        let (peer, diagnostics) = try expand("func load(); func loadCalls(_ value: Int)")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("var loadCalls: [LoadCall]"))
        #expect(peer.contains("func loadCalls(_ value: Int)"))
    }

    @Test("The missing-stub error constructor cannot bind to a protocol method")
    func reservesMissingStubError() throws {
        let (peer, diagnostics) = try expand("func load() throws -> Int; func _InnoDIMockNotStubbed(selector: String) -> String")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("struct _InnoDIMockNotStubbed2: Error"))
        #expect(peer.contains(".failure(_InnoDIMockNotStubbed2(selector:"))
        #expect(peer.contains("func _InnoDIMockNotStubbed(selector: String)"))
    }

    @Test("Concurrent reset uses a type-directed snapshot initializer")
    func disambiguatesSnapshotConstructor() throws {
        let (peer, diagnostics) = try expand(
            "func InnoDICallHistorySnapshot(generation: UInt64, recordedCallCounts: [String: Int]) -> Int",
            inheritance: ": Sendable"
        )
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("let snapshot: InnoDICallHistorySnapshot = .init("))
    }

    @Test("Protocol Self binds to the final mock in both witnesses and nested storage")
    func bindsSelfToMock() throws {
        let (peer, diagnostics) = try expand("""
            func copy() -> Self
            func compare(_ other: Self)
            var next: Self { get }
            func genericCopy<T>(_ value: T) -> Self
            """)
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("let other: BoundaryMock"))
        #expect(peer.contains("func copy() -> BoundaryMock"))
        #expect(peer.contains("func compare(_ other: BoundaryMock)"))
        #expect(peer.contains("var next: BoundaryMock"))
        #expect(peer.contains("func genericCopy<T>(_ value: T) -> BoundaryMock"))
    }

    @Test("Concrete Self bindings cannot be captured by generic type parameter names")
    func bindsSelfOutsideGenericScope() throws {
        let (peer, diagnostics) = try expand("func copy<BoundaryMock, _InnoDIMockSelf>(_ value: BoundaryMock, as type: _InnoDIMockSelf.Type) -> Self")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("typealias _InnoDIMockSelf2 = BoundaryMock"))
        #expect(peer.contains("-> _InnoDIMockSelf2"))
        #expect(peer.contains("as? _InnoDIMockSelf2"))
    }

    @Test("Explicit nonisolated protocols keep that boundary on generated mocks")
    func preservesNonisolatedProtocol() throws {
        let (peer, diagnostics) = try expand("func load() -> Int", modifier: "nonisolated ")
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("nonisolated final class BoundaryMock"))
    }

    private func expand(
        _ requirements: String,
        inheritance: String = "",
        modifier: String = ""
    ) throws -> (String, [Diagnostic]) {
        let parsed = Parser.parse(source: "@GenerateMock \(modifier)protocol Boundary\(inheritance) {\n\(requirements)\n}")
        let declaration = try #require(parsed.statements.first?.item.as(ProtocolDeclSyntax.self))
        let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(of: attribute, providingPeersOf: declaration, in: context)
        return (peers.map(\.description).joined(), context.diagnostics)
    }
}
