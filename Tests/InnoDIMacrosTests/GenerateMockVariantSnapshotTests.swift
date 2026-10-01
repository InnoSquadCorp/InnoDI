import InnoDITestSupport
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Golden expansions for every supported `@GenerateMock` shape. RFC 0001's
/// GA criterion 2 requires one snapshot per in-scope variant, and these
/// snapshots also pin the renderer's exact text while its string assembly is
/// replaced with syntax builders.
@Suite("GenerateMock variant snapshots")
struct GenerateMockVariantSnapshotTests {
    private static let macros: [String: any Macro.Type] = [
        "GenerateMock": GenerateMockMacro.self,
    ]

    @Test("Synchronous functions and properties")
    func synchronousShapes() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Catalog {
                var title: String { get set }
                var count: Int { get }
                func item(at index: Int) -> String
                func reload()
                mutating func reset(to value: Int)
            }
            """,
            matches: "synchronousShapes",
            macros: Self.macros
        )
    }

    @Test("Asynchronous functions without throws")
    func asynchronousShapes() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Loader {
                func load(path: String) async -> Data
                func warmUp() async
            }
            """,
            matches: "asynchronousShapes",
            macros: Self.macros
        )
    }

    @Test("Untyped and typed throws")
    func throwingShapes() {
        assertMacroExpansionSnapshot(
            """
            enum LoadFailure: Error { case missing }

            @GenerateMock
            protocol Parser {
                func parse(_ text: String) throws -> Int
                func validate(_ text: String) throws
                func decode(_ text: String) throws(LoadFailure) -> Int
                func check(_ text: String) async throws(LoadFailure)
            }
            """,
            matches: "throwingShapes",
            macros: Self.macros
        )
    }

    @Test("Generic methods with erased handlers")
    func genericShapes() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Store {
                func value<Value: Decodable>(for key: String, as type: Value.Type) -> Value
                func save<Value>(_ value: Value, for key: String) async throws where Value: Encodable
            }
            """,
            matches: "genericShapes",
            macros: Self.macros
        )
    }

    @Test("Overloaded methods")
    func overloadedShapes() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Formatter {
                func format(_ value: Int) -> String
                func format(_ value: Double) -> String
                func format(_ value: Int, width: Int) throws -> String
            }
            """,
            matches: "overloadedShapes",
            macros: Self.macros
        )
    }

    @Test("Sendable protocols with lock-backed storage")
    func sendableShapes() {
        assertMacroExpansionSnapshot(
            """
            enum SharedFailure: Error { case unavailable }

            @GenerateMock
            protocol SharedAPI: Sendable {
                var title: String { get set }
                func load() throws(SharedFailure) -> String
                func refresh(id: Int) async throws
                func ping()
            }
            """,
            matches: "sendableShapes",
            macros: Self.macros
        )
    }

    @Test("Main-actor protocols")
    func mainActorShapes() {
        assertMacroExpansionSnapshot(
            """
            @MainActor
            @GenerateMock
            protocol ScreenModel {
                var isLoading: Bool { get }
                func present(_ message: String)
                func refresh() async throws -> [String]
            }
            """,
            matches: "mainActorShapes",
            macros: Self.macros
        )
    }

    @Test("Escaping closures, optional returns, and explicit unit returns")
    func parameterAndReturnShapes() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            protocol Scheduler {
                func schedule(_ work: @escaping @Sendable () -> Void) -> (() -> Void)?
                func cancel(_: Int, reason: String) -> ()
                func lookup(`default`: String) -> String?
            }
            """,
            matches: "parameterAndReturnShapes",
            macros: Self.macros
        )
    }

    @Test("File-private protocols keep their access level")
    func fileprivateShapes() {
        assertMacroExpansionSnapshot(
            """
            @GenerateMock
            fileprivate protocol Clock: AnyObject {
                var now: Double { get }
            }
            """,
            matches: "fileprivateShapes",
            macros: Self.macros
        )
    }
}
