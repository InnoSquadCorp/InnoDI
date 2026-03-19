import SwiftParser
import SwiftDiagnostics
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
    func validateFalseStillRejectsMissingSharedFactory() throws {
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

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("@Provide(.shared) requires factory: <expr>, type: Type.self, or property initializer.") })
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

    @Test("input scope rejects type-based dependency wiring")
    func inputScopeRejectsWithDependencies() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.input, APIClient.self, with: [\\.config])
            var apiClient: APIClient
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer with invalid input wiring")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(
            of: attr,
            providingMembersOf: decl,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.message.contains("@Provide(.input) should not include a factory")
            }
        )
    }

    @Test
    func detectsContainerDependencyCycle() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.transient, factory: { (serviceB: ServiceB) in
                ServiceA(serviceB: serviceB)
            }, concrete: true)
            var serviceA: ServiceA

            @Provide(.transient, factory: { (serviceA: ServiceA) in
                ServiceB(serviceA: serviceA)
            }, concrete: true)
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
        #expect(context.diagnostics.contains { $0.message.contains("missing") })
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")
        })
    }

    @Test
    func validateDAGFalseSkipsCycleValidation() throws {
        let source = """
        @DIContainer(validateDAG: false)
        struct AppContainer {
            @Provide(.transient, factory: { (serviceB: ServiceB) in
                ServiceA(serviceB: serviceB)
            }, concrete: true)
            var serviceA: ServiceA

            @Provide(.transient, factory: { (serviceA: ServiceA) in
                ServiceB(serviceA: serviceA)
            }, concrete: true)
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

    @Test("String literal tokens do not trigger false dependency cycles")
    func stringLiteralTokensDoNotTriggerFalseDependencyCycles() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, concrete: true)
            var a: ServiceA = ServiceA(name: "b")

            @Provide(.shared, concrete: true)
            var b: ServiceB = ServiceB(name: "a")
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

        #expect(!generated.isEmpty)
        #expect(!context.diagnostics.contains { $0.message.contains("Dependency cycle detected in container") })
    }

    @Test("mainActor: true annotates generated init with @MainActor")
    func mainActorContainerGeneratesMainActorInit() throws {
        let source = """
        @DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.last?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer(mainActor: true)")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        #expect(generated.first?.description.contains("@MainActor") == true)
        #expect(context.diagnostics.isEmpty)
    }

    @Test("mainActor option conflicts with existing custom global actor")
    func mainActorConflictProducesDiagnostic() throws {
        let source = """
        @FeatureActor
        @DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.last?.as(AttributeSyntax.self) else {
            Issue.record("Should parse conflicting actor attributes")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("FeatureActor") })
    }

    @Test("asyncFactory and factory cannot be used together")
    func asyncFactoryAndFactoryConflictProducesDiagnostic() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.transient, factory: Service(), asyncFactory: { () async in Service() }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer with factory/asyncFactory conflict")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.factory-conflict")
            }
        )
    }

    @Test("input scope rejects asyncFactory")
    func inputScopeRejectsAsyncFactory() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input, asyncFactory: { () async in Service() }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer input asyncFactory")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(
            context.diagnostics.contains {
                $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.async-factory-invalid-scope")
            }
        )
    }

    @Test("asyncFactory must be async closure")
    func asyncFactoryMustBeAsyncClosure() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.transient, asyncFactory: { Service() }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer invalid asyncFactory")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("must be an async closure") })
    }

    @Test("async shared factory generates task-backed initialization")
    func asyncSharedFactoryGeneratesTaskBackedInit() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.shared, asyncFactory: { (config: Config) async in Service(config: config) }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse @DIContainer async shared factory")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        let initCode = generated.first?.description ?? ""
        #expect(initCode.contains("_storage_task_service"))
        #expect(initCode.contains("Task<"))
        #expect(initCode.contains("await"))
        #expect(context.diagnostics.isEmpty)
    }

    @Test("Factory parameter names must resolve by name without positional fallback")
    func factoryParameterNamesMustResolveStrictly() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.input)
            var logger: Logger

            @Provide(.shared, factory: { (wrongName: Config, logger: Logger) in
                Service(config: wrongName, logger: logger)
            }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse strict factory parameter case")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("wrongName") })
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        })
    }

    @Test("Reordered factory parameters are allowed when names match")
    func reorderedFactoryParametersRemainValid() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.input)
            var logger: Logger

            @Provide(.shared, factory: { (logger: Logger, config: Config) in
                Service(config: config, logger: logger)
            }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse reordered factory parameter case")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test("Sync shared dependencies cannot reference later shared members")
    func syncSharedDependenciesRejectForwardReferences() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.shared, factory: { (laterService: LaterService) in
                Service(laterService: laterService)
            }, concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(config: config), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse forward reference case")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("laterService") })
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
        })
    }

    @Test("with: dependencies reject later shared members")
    func withDependenciesRejectForwardReferences() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.shared, Service.self, with: [\\.laterService], concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(config: config), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse with forward reference case")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("laterService") })
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
        })
    }

    @Test("Async shared dependencies cannot reference later async shared members")
    func asyncSharedDependenciesRejectForwardReferences() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            @Provide(.shared, asyncFactory: { (laterService: LaterService) async in
                Service(laterService: laterService)
            }, concrete: true)
            var service: Service

            @Provide(.shared, asyncFactory: { (config: Config) async in
                LaterService(config: config)
            }, concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse async forward reference case")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains { $0.message.contains("laterService") })
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
        })
    }

    @Test("Custom init inside container body is rejected explicitly")
    func customInitInsideContainerBodyIsRejected() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            init(config: Config) {
                self.config = config
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse custom init container")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        })
    }

    @Test("Custom init inside same-file extension is rejected explicitly")
    func customInitInsideSameFileExtensionIsRejected() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse container with same-file extension init")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        })
    }

    @Test("Other same-file extensions do not trigger custom init rejection")
    func customInitInOtherSameFileExtensionDoesNotTriggerRejection() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        struct Helper {
            let value: Int
        }

        extension Helper {
            init(value: Int, doubled: Bool) {
                self.init(value: value * (doubled ? 2 : 1))
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse container with unrelated extension init")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test("All offending initializers in body and same-file extension are diagnosed")
    func allOffendingInitializersAreDiagnosed() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            init(config: Config) {
                self.config = config
            }
        }

        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }

            init(config: Config, retries: Int) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse container with multiple offending inits")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let diagnostics = context.diagnostics.filter {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        }

        #expect(generated.isEmpty)
        #expect(diagnostics.count == 3)
    }

    @Test("Cross-file extension initializers are outside the current detection policy")
    func crossFileExtensionInitializersAreIgnored() throws {
        let containerSource = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """
        let extensionSource = """
        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsedContainer = Parser.parse(source: containerSource)
        _ = Parser.parse(source: extensionSource)

        guard let decl = parsedContainer.statements.first?.item.as(StructDeclSyntax.self) else {
            Issue.record("Should parse cross-file policy fixture")
            return
        }

        let initializers = DIContainerParser.userDefinedInitializers(in: decl)
        #expect(initializers.isEmpty)
    }

    @Test("Nested same-file extensions for the annotated type are rejected")
    func nestedSameFileExtensionInitializersAreRejected() throws {
        let source = """
        struct Outer {
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config
            }
        }

        extension Outer.AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let outerDecl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let nestedDecl = outerDecl.memberBlock.members.first?.decl.as(StructDeclSyntax.self),
              let attr = nestedDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse nested container")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: nestedDecl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        })
    }

    @Test("Generic argument same-file extensions are excluded from custom init detection")
    func genericArgumentExtensionsAreExcluded() throws {
        let source = """
        @DIContainer
        struct AppContainer<T> {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer<String> {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse generic argument extension fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test("Constrained same-file extensions are excluded from custom init detection")
    func constrainedExtensionsAreExcluded() throws {
        let source = """
        @DIContainer
        struct AppContainer<T> {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer where T: Sendable {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse constrained extension fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(!generated.isEmpty)
        #expect(context.diagnostics.isEmpty)
    }

    @Test("Factory parameter diagnostics include notes and a unique rename fix-it")
    func unresolvedFactoryParameterDiagnosticsIncludeRenameFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var baseURL: String

            @Provide(.shared, factory: { (base_url: String) in
                Service(baseURL: base_url)
            }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(!diagnostic.notes.isEmpty)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("baseURL") == true)
    }

    @Test("Factory parameter diagnostics skip fix-its when multiple candidates exist")
    func unresolvedFactoryParameterDiagnosticsSkipAmbiguousFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var apiClient: APIClient

            @Provide(.input)
            var api_client: APIClient

            @Provide(.shared, factory: { (apiclient: APIClient) in
                Service(client: apiclient)
            }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse ambiguous unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(diagnostic.notes.count == 2)
        #expect(diagnostic.fixIts.isEmpty)
    }

    @Test("with dependency diagnostics include notes and a unique replacement fix-it")
    func unresolvedWithDependencyDiagnosticsIncludeReplacementFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var baseURL: String

            @Provide(.shared, Service.self, with: [\\.base_url], concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unresolved with dependency fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")
        }) else {
            Issue.record("Expected unresolved with dependency diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(!diagnostic.notes.isEmpty)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("\\.baseURL") == true)
    }

    @Test("Unavailable dependency diagnostics explain declaration-order constraints")
    func unavailableDependencyDiagnosticsIncludeNotes() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (laterService: LaterService) in
                Service(laterService: laterService)
            }, concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unavailable dependency fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
        }) else {
            Issue.record("Expected unavailable dependency diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(!diagnostic.notes.isEmpty)
        #expect(diagnostic.fixIts.isEmpty)
    }

    @Test("Custom init diagnostics include guidance notes and no fix-it")
    func customInitDiagnosticsIncludeGuidanceNotes() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            init(config: Config) {
                self.config = config
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse custom init guidance fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        }) else {
            Issue.record("Expected custom init diagnostic")
            return
        }

        #expect(diagnostic.notes.count == 2)
        #expect(diagnostic.fixIts.isEmpty)
    }

    @Test("Concrete opt-in diagnostics include guidance notes and a safe fix-it")
    func concreteOptInDiagnosticsIncludeSafeFixIt() throws {
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
            Issue.record("Should parse concrete opt-in fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required")
        }) else {
            Issue.record("Expected concrete opt-in diagnostic")
            return
        }

        #expect(diagnostic.notes.count == 2)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("concrete: true") == true)
    }
}
