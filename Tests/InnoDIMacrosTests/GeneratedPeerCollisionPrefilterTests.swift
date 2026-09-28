import Foundation
import InnoDICore
import InnoDITestSupport
import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("Generated peer collision prefilter")
struct GeneratedPeerCollisionPrefilterTests {
    @Test("Every emitted peer shape is included in the conservative prefilter")
    func everyShapeIsIncluded() {
        for scope: ProvideScope in [.input, .shared, .transient] {
            for isAsync in [false, true] {
                let shape = ManagedGeneratedSymbolShape.provide(scope: scope, isAsync: isAsync)
                #expect(Set(shape.symbolNames(for: "")).isSubset(of: ManagedGeneratedSymbolShape.possiblePrefixes))
            }
        }
        for scope: SubContainerScopeValue in [.shared, .transient] {
            let shape = ManagedGeneratedSymbolShape.subContainer(scope: scope)
            #expect(Set(shape.symbolNames(for: "")).isSubset(of: ManagedGeneratedSymbolShape.possiblePrefixes))
        }
        #expect(!hasPotentialGeneratedPeerSymbolCollision(memberNames: ["config", "api", "service", "child"]))
        #expect(hasPotentialGeneratedPeerSymbolCollision(memberNames: ["api", "task_api"]))
        #expect(hasPotentialGeneratedPeerSymbolCollision(memberNames: ["child", "sub_child"]))
        #expect(hasPotentialGeneratedPeerSymbolCollision(memberNames: ["child", "apply_child"]))
    }

    @Test("Prefilter preserves scope-aware collisions and non-colliding controls")
    func preservesExactValidation() throws {
        let declarations = [
            "@Input var NAME: Int",
            "@Provide(.shared) var NAME: Int = 1",
            "@Provide(.shared, asyncFactory: { 1 }) var NAME: Int",
            "@Provide(.transient) var NAME: Int = 1",
            "@SubContainer(scope: .shared) var NAME: Child",
            "@SubContainer(scope: .transient) var NAME: Child",
        ]
        let names = ["item", "task_item", "sub_item", "sub_apply_item", "apply_item", "unrelated"]
        for first in declarations {
            for second in declarations {
                for name in names {
                    let source = """
                    @DIContainer struct Container {
                        \(first.replacingOccurrences(of: "NAME", with: "item"))
                        \(second.replacingOccurrences(of: "NAME", with: name))
                    }
                    """
                    let parsed = Parser.parse(source: source)
                    let declaration = try #require(parsed.statements.first?.item.as(StructDeclSyntax.self))
                    if name == "item" {
                        // Duplicate user names are rejected before a model is
                        // returned and do not claim generated peer names.
                        #expect(!hasGeneratedPeerSymbolCollision(in: declaration))
                        continue
                    }
                    let model = try #require(DIContainerParser.parse(
                        declaration: declaration,
                        context: TestMacroExpansionContext()
                    ))
                    let expected = !generatedPeerSymbolCollisions(in: model).isEmpty
                    #expect(hasGeneratedPeerSymbolCollision(in: declaration) == expected, Comment(rawValue: source))
                }
            }
        }
    }
}
