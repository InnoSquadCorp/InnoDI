import Foundation
import InnoDICore
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INNODI_RUN_MACRO_TESTS"] == "1"))
struct DIContainerMacroTests {
    @Test
    func parseProvideAttributes() throws {
        let source = """
        @Provide(.input)
        var bar: Int
        """
        
        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }
        
        let args = parseProvideArguments(attr)
        #expect(args.scope == .input)
        #expect(args.factoryExpr == nil)
    }
    
    @Test
    func parseProvideWithFactory() throws {
        let source = """
        @Provide(.shared, factory: SomeType())
        var foo: SomeProtocol
        """
        
        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }
        
        let args = parseProvideArguments(attr)
        #expect(args.scope == .shared)
        #expect(args.factoryExpr != nil)
        #expect(args.factoryExpr!.description.contains("SomeType"))
    }
    
    @Test
    func parseProvideWithTypeAndDependencies() throws {
        let source = """
        @Provide(.shared, APIClient.self, with: [\\.config, \\.logger])
        var apiClient: APIClientProtocol
        """
        
        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide")
            return
        }
        
        let args = parseProvideArguments(attr)
        #expect(args.scope == .shared)
        #expect(args.typeExpr != nil)
        #expect(args.dependencies == ["config", "logger"])
    }

    @Test
    func transientFactoryClosureInjectsDependenciesByParameterName() throws {
        let source = """
        @Provide(.transient, factory: { (apiClient: APIClient) in ViewModel(apiClient: apiClient) })
        var viewModel: ViewModel
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide with transient factory closure")
            return
        }

        let context = TestMacroExpansionContext()
        let accessors = try ProvideMacro.expansion(
            of: attr,
            providingAccessorsOf: varDecl,
            in: context
        )

        let generated = accessors.map(\.description).joined(separator: "\n")
        #expect(generated.contains("self.apiClient"))
    }
}

private final class TestMacroExpansionContext: MacroExpansionContext {
    var lexicalContext: [Syntax] { [] }

    func makeUniqueName(_ name: String) -> TokenSyntax {
        .identifier(name)
    }

    func diagnose(_ diagnostic: Diagnostic) {}

    func location(
        of node: some SyntaxProtocol,
        at position: PositionInSyntaxNode,
        filePathMode: SourceLocationFilePathMode
    ) -> AbstractSourceLocation? {
        nil
    }
}
