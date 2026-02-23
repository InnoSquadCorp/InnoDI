import SwiftParser
import SwiftSyntax
import Testing

@testable import InnoDIMacros

@Suite("DIContainer Macro Tests")
struct DIContainerMacroTests {
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

    @Test("Bare protocol type requires concrete opt-in for shared dependency")
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

    @Test("Bare optional protocol type requires concrete opt-in for shared dependency")
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

    @Test("Explicit any protocol shared dependency does not require concrete opt-in")
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

    @Test("Optional any protocol shared dependency does not require concrete opt-in")
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

    @Test("Opaque some protocol shared dependency does not require concrete opt-in")
    func someProtocolSharedDependencyDoesNotRequireOptIn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: APIClient())
            var apiClient: some APIClientProtocol = APIClient()
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

    @Test("Protocol composition shared dependency does not require concrete opt-in")
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
    func validateFalseStillRejectsConcreteDependencyWithoutOptIn() throws {
        let source = """
        @DIContainer(validate: false)
        struct AppContainer {
            @Provide(.shared, factory: Service())
            var service: Service
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
        #expect(context.diagnostics.contains { $0.message.contains("requires concrete: true") })
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

    @Test
    func detectsContainerDependencyCycle() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: ServiceA(serviceB: serviceB), concrete: true)
            var serviceA: ServiceA

            @Provide(.shared, factory: ServiceB(serviceA: serviceA), concrete: true)
            var serviceB: ServiceB
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("Dependency cycle detected in container") })
    }

    @Test
    func detectsUnknownDependencyInWithClause() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.shared, APIClient.self, with: [\\.missing], concrete: true)
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
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("Unknown dependency 'missing'") })
    }

    @Test
    func validateDAGFalseSkipsCycleValidation() throws {
        let source = """
        @DIContainer(validateDAG: false)
        struct AppContainer {
            @Provide(.shared, factory: ServiceA(serviceB: serviceB), concrete: true)
            var serviceA: ServiceA

            @Provide(.shared, factory: ServiceB(serviceA: serviceA), concrete: true)
            var serviceB: ServiceB
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer(validateDAG: false)")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }
}
