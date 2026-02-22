import InnoDICore
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

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

    @Test
    func concreteSharedDependencyRequiresOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: APIClient
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("requires concrete: true") })
    }

    @Test
    func bareProtocolSharedDependencyRequiresOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: APIClientProtocol
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("requires concrete: true") })
    }

    @Test
    func bareOptionalProtocolSharedDependencyRequiresOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: APIClientProtocol?
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("requires concrete: true") })
    }

    @Test
    func anyProtocolSharedDependencyDoesNotRequireOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: any APIClientProtocol
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func optionalAnyProtocolSharedDependencyDoesNotRequireOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: (any APIClientProtocol)?
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func someProtocolSharedDependencyDoesNotRequireOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: some APIClientProtocol
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func compositionSharedDependencyDoesNotRequireOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: APIClientProtocol & LoggerProtocol
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func concreteSharedDependencyWithOptInGeneratesInit() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient(), concrete: true)
            var apiClient: APIClient
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(!generated.isEmpty)
        let initCode = generated.first?.description ?? ""
        #expect(initCode.contains("apiClient"))
        #expect(initCode.contains("_storage_apiClient"))
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func validateFalseAllowsMissingSharedFactoryWithRuntimeFallback() throws {
        let source = """
        @DIContainer(validate: false)
        struct AppContainer {
            @Provide(.shared)
            var service: any ServiceProtocol
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer(validate: false)")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(!generated.isEmpty)
        #expect(generated.first?.description.contains("Missing factory for shared dependency 'service'.") == true)
        #expect(context.diagnostics.isEmpty)
    }

    @Test
    func validateFalseStillRejectsInputFactory() throws {
        let source = """
        @DIContainer(validate: false)
        struct AppContainer {
            @Provide(.input, factory: Service())
            var service: any ServiceProtocol
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer(validate: false)")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("@Provide(.input) should not include a factory") })
    }
}

private final class TestMacroExpansionContext: MacroExpansionContext {
    var diagnostics: [Diagnostic] = []
    var lexicalContext: [Syntax] { [] }

    func makeUniqueName(_ name: String) -> TokenSyntax {
        .identifier(name)
    }

    func diagnose(_ diagnostic: Diagnostic) {
        diagnostics.append(diagnostic)
    }

    func location(
        of node: some SyntaxProtocol,
        at position: PositionInSyntaxNode,
        filePathMode: SourceLocationFilePathMode
    ) -> AbstractSourceLocation? {
        nil
    }
}
