import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Shapes that `@GenerateMock` once accepted and then expanded to a mock that
/// did not compile, or compiled and misbehaved. Each snapshot holds the shape
/// next to a control that always expanded correctly;
/// `Tests/InnoDITestingTests/GenerateMockShapeTests.swift` compiles and runs
/// the same shapes against the real macro.
@Suite("GenerateMock shape regressions")
struct GenerateMockShapeRegressionTests {
    private static let macros: [String: any Macro.Type] = [
        "GenerateMock": GenerateMockMacro.self,
    ]

    private static let unsupportedMember = MessageID(
        domain: "InnoDI.validation",
        id: "mock.unsupported-member"
    )

    // MARK: - G1 `where Self:` refinements

    @Test("A where-clause Sendable refinement selects lock-backed storage")
    func whereSendableSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol WhereShared where Self: Sendable {
                func ping() -> Int
            }
            @GenerateMock
            protocol WhereClassBound where Self: AnyObject {
                func ping() -> Int
            }
            """,
            matches: "whereSelfRefinements",
            macros: Self.macros
        )
    }

    @Test("A where-clause refinement of another protocol or class fails closed", arguments: [
        ("protocol Child where Self: Parent { func childWork() }", "Parent inheritance"),
        ("protocol Presentable where Self: Base { func present() }", "Base inheritance"),
        ("protocol Both where Self: Sendable & Parent { func work() }", "Sendable & Parent inheritance"),
        ("protocol Element where Self.Element: Hashable { func work() }", "where Self.Element: Hashable requirement"),
    ])
    func whereRefinementFailsClosed(_ declaration: String, reason: String) throws {
        assertMacroExpansionDiagnosticCodes(
            "@GenerateMock\n\(declaration)",
            expectedCodes: [Self.unsupportedMember],
            macros: Self.macros
        )
        let (peer, diagnostics) = try expand("@GenerateMock\n\(declaration)")
        #expect(peer.isEmpty)
        #expect(diagnostics.first?.message.contains(reason) == true)
    }

    @Test("Inheritance controls keep their behavior")
    func inheritanceControls() throws {
        let (sendablePeer, sendableDiagnostics) = try expand("""
            @GenerateMock
            protocol Shared: Sendable { func ping() -> Int }
            """)
        #expect(sendableDiagnostics.isEmpty)
        #expect(sendablePeer.contains("InnoDITesting.DIConcurrentMockState()"))

        let (parentPeer, parentDiagnostics) = try expand("""
            @GenerateMock
            protocol Child: Parent { func childWork() }
            """)
        #expect(parentPeer.isEmpty)
        #expect(parentDiagnostics.first?.message.contains("Parent inheritance") == true)
    }

    // MARK: - G2 / G3 captured ownership and `sending` arguments

    @Test("Sendable mocks capture each ownership and sending argument on its own line")
    func sendableCapturesSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol SharedMover: Sendable {
                func move(_ from: borrowing String, _ to: consuming String)
                func send(_ value: sending String)
                func single(_ from: borrowing String, _ to: String)
                func plain(_ value: String)
            }
            @GenerateMock
            protocol Mover {
                func move(_ from: borrowing String, _ to: consuming String)
                func send(_ value: sending String)
            }
            """,
            matches: "sendableOwnershipCaptures",
            macros: Self.macros
        )
    }

    // MARK: - G4 call records and signature types

    @Test("Call records yield to same-named types spelled in any requirement")
    func callRecordTypeNamesSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol ToolRunner {
                func tool(named name: String) -> ToolCall
                func start(_ call: StartCall)
                func fetch()
                func log(_ entry: FetchCall.Kind)
                func scoped<LoadCall>(_ value: LoadCall)
                func load()
            }
            @GenerateMock
            protocol ToolInvocations {
                func tool(named name: String) -> ToolInvocation
            }
            """,
            matches: "callRecordTypeNames",
            macros: Self.macros
        )
    }

    // MARK: - G5 / G7 / G8 optional spellings

    @Test("Stubs follow the syntax of optional, function, and implicitly unwrapped types")
    func optionalSpellingsSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Spellings {
                func loader() -> () -> Int?
                var parse: (String) -> Int? { get set }
                func plain() -> () -> Int
                func optionalLoader() -> (() -> Int)?
                var name: String! { get set }
                func find() -> String!
                func lookup() throws -> String!
                func accept(_ value: String!)
                func sugar() -> Int?
                func named() -> Optional<Int>
                func qualified() -> Swift.Optional<Int>
                func parenthesized() -> (Int?)
                func aliased() -> MaybeInt
                var optionalName: Optional<String> { get set }
            }
            @GenerateMock
            protocol SharedSpellings: Sendable {
                func loader() -> @Sendable () -> Int?
                var parse: @Sendable (String) -> Int? { get set }
                func named() -> Optional<Int>
                func aliased() -> MaybeInt
            }
            """,
            matches: "optionalSpellings",
            macros: Self.macros
        )
    }

    // MARK: - G6 multi-line types

    @Test("Multi-line types stay out of string literals")
    func multiLineTypesSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Pager {
                func page() -> (
                    items: [Int], // first page
                    next: Int?
                )
                var cursor: (
                    offset: Int,
                    limit: Int
                ) { get set }
                func decode<T>(_ type: T.Type) -> (
                    value: T,
                    count: Int
                )
                func optionalPage() -> (
                    items: [Int],
                    next: Int?
                )?
                func single() -> (items: [Int], next: Int?)
            }
            """,
            matches: "multiLineTypes",
            macros: Self.macros
        )
    }

    // MARK: - G9 the untyped error existential

    @Test("Untyped errors use InnoDI's reserved Error alias")
    func reservedErrorAliasSnapshot() {
        assertMacroExpansionSnapshot(
            """
            enum Networking {
                enum Error: Swift.Error { case offline }
                @GenerateMock
                protocol Client {
                    func send() throws -> Int
                    func ping() throws
                }
                @GenerateMock
                protocol SharedClient: Sendable {
                    func send() throws -> Int
                    func ping() throws
                }
            }
            """,
            matches: "reservedErrorAlias",
            macros: Self.macros
        )
    }

    // MARK: - G10 member availability

    @Test("Member availability beyond InnoDI's platforms and the protocol fails closed", arguments: [
        "@available(macOS 99, *) func make() -> NewThing",
        "@available(iOS 18, *) func make() -> NewThing",
        "@available(macOS, introduced: 15) var thing: NewThing { get }",
        "@available(macOS, obsoleted: 15) func make() -> Int",
        "@available(*, unavailable) func make() -> Int",
        "@available(macOSApplicationExtension 15, *) func make() -> Int",
        "@available(driverOS 1, *) func make() -> Int",
    ])
    func memberAvailabilityFailsClosed(_ requirement: String) throws {
        let source = "@GenerateMock\nprotocol Uses {\n\(requirement)\n}"
        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [Self.unsupportedMember],
            macros: Self.macros
        )
        let (peer, diagnostics) = try expand(source)
        #expect(peer.isEmpty)
        #expect(diagnostics.first?.message.contains("platform @available cannot guard the mock's stored stubs") == true)
    }

    @Test("Availability guaranteed by InnoDI or an enclosing declaration keeps the mock")
    func guaranteedAvailabilityIsAccepted() throws {
        let accepted = [
            """
            @GenerateMock
            protocol Uses {
                @available(macOS 13, iOS 16, tvOS 17, watchOS 10, visionOS 1, *) func run() -> Int
                @available(macOS, introduced: 14) var title: String { get }
                @available(OSX 10.15, macCatalyst 17, *) func legacy()
                @available(swift 5.9) func modern()
                @available(*, deprecated, message: "Use run()") func old()
                @available(*, noasync) func blocking()
            }
            """,
            """
            @available(macOS 99, *)
            @GenerateMock
            protocol Uses {
                @available(macOS 99, *) func make() -> NewThing
            }
            """,
            """
            @GenerateMock
            @available(macOS, introduced: 99)
            protocol Uses {
                @available(macOS 98, *) func make() -> NewThing
            }
            """,
        ]
        for source in accepted {
            let (peer, diagnostics) = try expand(source)
            #expect(diagnostics.isEmpty, "\(source)")
            #expect(peer.contains("final class UsesMock: Uses"))
        }
    }

    @Test("An enclosing declaration's availability implies a member's")
    func enclosingAvailabilityIsAccepted() throws {
        assertMacroExpansionDiagnosticCodes(
            """
            @available(macOS 99, *)
            enum Future {
                @GenerateMock
                protocol Uses {
                    @available(macOS 99, *) func make() -> NewThing
                }
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("InnoDI's availability floor matches Package.swift's platforms")
    func availabilityFloorMatchesPackage() throws {
        let manifest = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let platforms = try #require(
            manifest.range(of: "platforms: [").map { start in
                manifest[start.upperBound...].prefix { $0 != "]" }
            }
        )
        var declared: [String: [Int]] = [:]
        for entry in platforms.split(separator: ",") {
            let parts = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                .dropFirst()
                .split(separator: "(")
            guard parts.count == 2 else { continue }
            let version = parts[1].dropFirst(2).prefix { $0 != ")" }
                .split(separator: "_")
                .compactMap { Int($0) }
            declared[String(parts[0])] = version
        }
        #expect(!declared.isEmpty)
        for (platform, version) in declared {
            #expect(innoDIMinimumPlatformVersions[platform] == version, "\(platform)")
        }
        #expect(innoDIMinimumPlatformVersions["macCatalyst"] == declared["iOS"])
        #expect(Set(innoDIMinimumPlatformVersions.keys) == Set(declared.keys).union(["macCatalyst"]))
    }

    // MARK: - G11 rare spellings

    @Test("Digit-leading stems and keyword-named arguments expand to valid helpers")
    func rareSpellingsSnapshot() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol RareSpellings {
                func _2fa() -> Bool
                func check(_1: Int)
                func schedule(await: Bool, `inout`: Int, copy: borrowing String)
            }
            @GenerateMock
            protocol SharedRareSpellings: Sendable {
                func schedule(await: Bool, `inout`: Int, copy: borrowing String)
            }
            """,
            matches: "rareSpellings",
            macros: Self.macros
        )
    }

    @Test("Parameter packs and structural opaque parameters fail closed", arguments: [
        ("func f<each T>(_ value: repeat each T)", "parameter packs"),
        ("func f<each T>() -> (repeat each T)", "parameter packs"),
        ("func consume(_ items: [some Sequence<Int>])", "consume"),
        ("func consume(_ items: (some Sequence<Int>)?)", "consume"),
    ])
    func unsupportedRareSpellings(_ requirement: String, reason: String) throws {
        let source = "@GenerateMock\nprotocol Rare {\n\(requirement)\n}"
        assertMacroExpansionDiagnosticCodes(
            source,
            expectedCodes: [Self.unsupportedMember],
            macros: Self.macros
        )
        let (peer, diagnostics) = try expand(source)
        #expect(peer.isEmpty)
        #expect(diagnostics.first?.message.contains(reason) == true)
    }

    @Test("A generic requirement keeps its erased opaque argument")
    func genericOpaqueArgumentControl() throws {
        let (peer, diagnostics) = try expand("""
            @GenerateMock
            protocol Rare { func u<T>(_ x: [some Sequence<Int>], _ y: T) -> Int }
            """)
        #expect(diagnostics.isEmpty)
        #expect(peer.contains("func u<T>(_ x: [some Sequence<Int>], _ y: T) -> Int"))
    }

    private func expand(_ source: String) throws -> (String, [Diagnostic]) {
        let parsed = Parser.parse(source: source)
        let declaration = try #require(parsed.statements.compactMap {
            $0.item.as(ProtocolDeclSyntax.self)
        }.first)
        let attribute = try #require(declaration.attributes.compactMap {
            $0.as(AttributeSyntax.self)
        }.first { $0.attributeName.trimmedDescription == "GenerateMock" })
        let context = TestMacroExpansionContext()
        let peers = try GenerateMockMacro.expansion(
            of: attribute,
            providingPeersOf: declaration,
            in: context
        )
        return (peers.map(\.description).joined(), context.diagnostics)
    }
}
