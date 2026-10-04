import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

@Suite("Owned container opt-in parsing")
struct ContainerOwnedParsingTests {
    @Test("Omitted and false options preserve legacy construction")
    func defaults() throws {
        #expect(try !parse("@DIContainer").generateOwned)
        #expect(try parse("@DIContainer").generateOwnedParseState == .omitted)
        #expect(try parse("@DIContainer(generateOwned: false)").generateOwnedParseState == .parsed(false))
        #expect(!DIContainerAttributeInfo(root: false, validateDAG: true, mainActor: false).generateOwned)
    }

    @Test("Both container spellings accept literal true", arguments: [
        "@DIContainer(generateOwned: true)",
        "@InnoDI.DIContainer(generateOwned: true)",
        "@DIContainerRole(role: ContainerRole.component, generateOwned: true)",
        "@InnoDI.DIContainerRole(role: InnoDI.ContainerRole.local, mainActor: true, generateOwned: true)"
    ])
    func literalTrue(_ attribute: String) throws {
        #expect(try parse(attribute).generateOwned)
    }

    @Test("Expressions and repeated options fail closed", arguments: [
        "flag", "1", "\"true\"", "choose()", "(true)",
        "true, generateOwned: false", "false, generateOwned: true"
    ])
    func invalid(_ value: String) throws {
        let parsed = try parse("@DIContainer(generateOwned: \(value))")
        #expect(parsed.generateOwnedParseState == .invalid)
        #expect(!parsed.generateOwned)
    }

    private func parse(_ attribute: String) throws -> DIContainerAttributeInfo {
        let syntax = Parser.parse(source: "\(attribute) struct Container {}")
        let declaration = try #require(syntax.statements.first?.item.as(StructDeclSyntax.self))
        return try #require(parseDIContainerAttribute(declaration.attributes))
    }
}
