import InnoDITestSupport
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Prepared owned operations")
struct PreparedContainerMacroTests {
    private var macros: [String: any Macro.Type] {
        var result = DIContainerMacroTests.macros
        result["DIContainerRole"] = DIContainerRoleMacro.self
        return result
    }

    @Test("Prepared operations require opt-in and asynchronous selections", arguments: ["", "(generateOwned: false)"])
    func legacyStaysLight(option: String) {
        let result = expandMacroSource("""
            @DIContainer\(option) struct Services {
                @Provide(.shared, asyncFactory: { () async in 1 }) var service: Int
            }
            """, macros: macros)
        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("withPrepared"))
        #expect(!result.expansion.contains("requireReady"))
    }

    @Test("Sync-only owned graph has no uninhabited prepared API")
    func syncOnly() {
        let result = expandMacroSource("""
            @DIContainer(generateOwned: true) struct Services {
                @Provide(.shared, factory: 1) var service: Int
                func withPrepared() {}
            }
            """, macros: macros)
        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("static func withPrepared"))
    }

    @Test("Prepared operation preserves isolation and structured cleanup", arguments: [false, true])
    func preparedShape(mainActor: Bool) throws {
        let result = expandMacroSource("""
            @DIContainerRole(role: ContainerRole.local, mainActor: \(mainActor), generateOwned: true)
            public struct Services {
                @Input public var input: Int
                @Provide(.shared, asyncFactory: { (input: Int) async in input }) public var service: Int
            }
            """, macros: macros)
        #expect(result.diagnostics.isEmpty)
        let tree = Parser.parse(source: result.expansion)
        let container = try #require(tree.statements.first?.item.as(StructDeclSyntax.self))
        let helper = try #require(container.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
            .first { $0.name.text == "withPrepared" })
        let parameters = helper.signature.parameterClause.parameters
        #expect(parameters.map(\.firstName.text) == ["_", "_", "input", "_innoDITrace", "overrides", "operation"])
        let callback = try #require(parameters.last).type.trimmedDescription
        #expect(callback.contains("@_Concurrency.MainActor") == mainActor)
        #expect(callback.contains("nonisolated(nonsending)") != mainActor)
        #expect(!callback.contains("Sendable"))
        let body = try #require(helper.body).statements
        #expect(body.count == 7)
        #expect(body[body.startIndex].description.contains("checkCancellation"))
        #expect(body[body.index(body.startIndex, offsetBy: 1)].description.contains("makeOwnedWithOverrides"))
        let guarded = body[body.index(body.startIndex, offsetBy: 3)].description
        let ready = try #require(guarded.range(of: "try _innoDIReport.requireReady()"))
        let operation = try #require(guarded.range(of: "try await _innoDIOperation"))
        #expect(ready.lowerBound < operation.lowerBound)
        #expect(guarded.contains("await _innoDIOwner.close()"))
        #expect(guarded.contains("throw error"))
        #expect(body[body.index(body.startIndex, offsetBy: 4)].description.contains("await _innoDIOwner.close()"))
        #expect(body[body.index(body.startIndex, offsetBy: 5)].description.contains("checkCancellation"))
        #expect(!helper.description.contains("Task {"))
        #expect(!helper.description.contains("Task.detached"))
        #expect(result.expansion.contains("func requireReady("))
        #expect(result.expansion.contains("func retryAndRequireReady("))
    }

    @Test("Prepared helper collision fails at an authored declaration")
    func collision() {
        let result = expandMacroSource("""
            @DIContainer(generateOwned: true) struct Services {
                @Provide(.shared, asyncFactory: { () async in 1 }) var service: Int
                func withPrepared() {}
            }
            """, macros: macros)
        #expect(result.diagnostics.contains { $0.message.contains("already uses 'withPrepared'") })
    }
}
