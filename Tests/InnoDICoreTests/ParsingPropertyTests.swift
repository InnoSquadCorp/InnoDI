import SwiftParser
import SwiftSyntax
import Testing

import InnoDITestSupport
@testable import InnoDICore

@Suite("Parsing Property Tests")
struct ParsingPropertyTests {
    @Test("parseProvideArguments keeps semantic result across shuffled arguments", arguments: Array(0..<200))
    func parseProvideArgumentsIsOrderStable(seed: Int) throws {
        var rng = SeededRandom(seed: UInt64(seed + 1))
        let scopes: [ProvideScope] = [.shared, .input, .transient]
        let selectedScope = scopes[rng.nextInt(upperBound: scopes.count)]
        let includeType = rng.nextBool()
        let includeWith = rng.nextBool()
        let includeFactory = rng.nextBool()
        let includeConcrete = rng.nextBool()

        var arguments: [String] = [".\(selectedScope.rawValue)"]
        if includeType {
            arguments.append("APIClient.self")
        }
        if includeWith {
            arguments.append("with: [\\.config, \\.logger]")
        }
        if includeFactory {
            arguments.append("factory: Foo()")
        }
        if includeConcrete {
            arguments.append("concrete: true")
        }

        let shuffledArguments = rng.shuffled(arguments)
        let source = """
        struct Container {
            @Provide(\(shuffledArguments.joined(separator: ", ")))
            var value: Value
        }
        """

        let file = Parser.parse(source: source)
        guard let structDecl = file.statements.first?.item.as(StructDeclSyntax.self),
              let varDecl = structDecl.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Expected container and @Provide declaration.")
            return
        }

        let parsed = parseProvideArguments(attr)

        #expect(parsed.scope == selectedScope)
        #expect((parsed.typeExpr != nil) == includeType)
        #expect((parsed.factoryExpr != nil) == includeFactory)
        #expect(parsed.concrete == includeConcrete)
        #expect(parsed.dependencies == (includeWith ? ["config", "logger"] : []))
    }
}
