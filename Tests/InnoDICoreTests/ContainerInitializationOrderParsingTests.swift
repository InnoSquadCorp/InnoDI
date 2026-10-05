import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDICore

@Suite("Container initialization order parsing")
struct ContainerInitializationOrderParsingTests {
    @Test("Omission and source-compatible initializer preserve declaration order")
    func defaultOrder() throws {
        let parsed = try parse("@DIContainer")
        #expect(parsed.initializationOrder == .declaration)
        #expect(parsed.initializationOrderParseState == .omitted)
        let constructed = DIContainerAttributeInfo(root: false, validateDAG: true, mainActor: false)
        #expect(constructed.initializationOrder == .declaration)
        #expect(constructed.initializationOrderParseState == .omitted)
    }

    @Test("Named tokens normalize for both container macros", arguments: [
        "@DIContainer(",
        "@InnoDI.DIContainer(",
        "@DIContainerRole(role: ContainerRole.component, ",
        "@InnoDI.DIContainerRole(role: InnoDI.ContainerRole.local, mainActor: true, ",
    ], ["ContainerInitializationOrder", "InnoDI.ContainerInitializationOrder"])
    func supportedTokens(prefix: String, namespace: String) throws {
        for value in [ContainerInitializationOrderValue.declaration, .dependency] {
            let parsed = try parse("\(prefix)initializationOrder: \(namespace).\(value.rawValue))")
            #expect(parsed.initializationOrder == value)
            #expect(parsed.initializationOrderParseState == .parsed(value))
        }
    }

    @Test("Unsupported expressions fail closed", arguments: [
        ".dependency", "\"dependency\"", "mode", "chooseMode()",
        "Other.ContainerInitializationOrder.dependency", "Other.dependency",
        "ContainerInitializationOrder.unknown", "(ContainerInitializationOrder.dependency)",
        "ContainerInitializationOrder.dependency()", "InnoDI.Other.ContainerInitializationOrder.dependency",
        "ContainerInitializationOrder.dependency, initializationOrder: ContainerInitializationOrder.declaration",
        "mode, initializationOrder: ContainerInitializationOrder.dependency",
    ])
    func invalidTokens(_ expression: String) throws {
        let parsed = try parse("@DIContainer(initializationOrder: \(expression))")
        #expect(parsed.initializationOrderParseState == .invalid)
        #expect(parsed.initializationOrder == .declaration)
    }

    @Test("Token identity is structural and permits source trivia")
    func qualifiedTokenTrivia() throws {
        let parsed = try parse("@DIContainer(initializationOrder: InnoDI /* module */ . ContainerInitializationOrder /* policy */ . dependency)")
        #expect(parsed.initializationOrder == .dependency)
    }

    private func parse(_ attribute: String) throws -> DIContainerAttributeInfo {
        let source = Parser.parse(source: "\(attribute) struct Container {}")
        let declaration = try #require(source.statements.first?.item.as(StructDeclSyntax.self))
        return try #require(parseDIContainerAttribute(declaration.attributes))
    }
}
