import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("Provide Macro Tests")
struct ProvideMacroTests {
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
        #expect(generated.contains("_override_viewModel"))
        #expect(generated.contains("{ (apiClient: APIClient) in ViewModel(apiClient: apiClient) }"))
        #expect(generated.contains("(self.apiClient)"))
        #expect(generated.contains("self.apiClient"))
    }

    @Test
    func transientFactoryClosureWithNoParametersDoesNotInjectDependencies() throws {
        let source = """
        @Provide(.transient, factory: { ViewModel() })
        var viewModel: ViewModel
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide with parameterless transient factory closure")
            return
        }

        let context = TestMacroExpansionContext()
        let accessors = try ProvideMacro.expansion(
            of: attr,
            providingAccessorsOf: varDecl,
            in: context
        )

        let generated = accessors.map(\.description).joined(separator: "\n")
        #expect(generated.contains("{ ViewModel() }()"))
        #expect(!generated.contains("self."))
    }

    @Test
    func transientFactoryClosureInjectsAllDependenciesForMultipleParameters() throws {
        let source = """
        @Provide(.transient, factory: { (apiClient: APIClient, logger: Logger) in ViewModel(apiClient: apiClient, logger: logger) })
        var viewModel: ViewModel
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide with multi-parameter transient factory closure")
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
        #expect(generated.contains("self.logger"))
    }

    @Test("Transient type factory with with: injects dependencies via accessors")
    func transientTypeFactoryWithDependenciesUsesAccessorInjection() throws {
        let source = """
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.transient, ViewModel.self, with: [\\.config])
            var viewModel: ViewModel
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let targetVarDecl = decl.memberBlock.members
                  .compactMap({ $0.decl.as(VariableDeclSyntax.self) })
                  .first(where: { varDecl in
                      guard let binding = varDecl.bindings.first,
                            let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                          return false
                      }
                      return identifier.identifier.text == "viewModel"
                  }),
              let attr = targetVarDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse target @Provide(.transient, Type.self, with: ...)")
            return
        }

        let context = TestMacroExpansionContext()
        let accessors = try ProvideMacro.expansion(
            of: attr,
            providingAccessorsOf: targetVarDecl,
            in: context
        )

        let generated = accessors.map(\.description).joined(separator: "\n")
        #expect(generated.contains("self.config"))
        #expect(!generated.contains("_storage_config"))
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func transientFactoryClosureWithUnderscoreParameterEmitsDiagnostic() throws {
        let source = """
        @Provide(.transient, factory: { (_: APIClient, logger: Logger) in ViewModel(logger: logger) })
        var viewModel: ViewModel
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @Provide with underscore transient factory closure")
            return
        }

        let context = TestMacroExpansionContext()
        let accessors = try ProvideMacro.expansion(
            of: attr,
            providingAccessorsOf: varDecl,
            in: context
        )

        let generated = accessors.map(\.description).joined(separator: "\n")
        #expect(generated.contains("Transient factory closure parameters must be named for injection."))
        #expect(!generated.contains("self._"))
        #expect(context.diagnostics.contains { $0.message.contains("must be named for injection") })
    }

    @Test("Closure parameter parser skips wildcard placeholders and keeps named args")
    func parseClosureParameterNamesSkipsWildcard() throws {
        let source = """
        @Provide(.transient, factory: { (_: APIClient, logger: Logger) in ViewModel(logger: logger) })
        var viewModel: ViewModel
        """

        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attr = varDecl.attributes.first?.as(AttributeSyntax.self),
              let closure = parseProvideArguments(attr).factoryExpr?.as(ClosureExprSyntax.self) else {
            Issue.record("Should parse transient factory closure")
            return
        }

        let parameterList = parseClosureParameterNames(closure)
        #expect(parameterList.hasWildcard == true)
        #expect(parameterList.names == ["logger"])
    }
}
