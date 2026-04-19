import InnoDITestSupport
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("DIContainer Macro Tests")
struct DIContainerMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
    ]

    @Test
    func concreteSharedDependencyRequiresOptIn() {
        assertMacroExpansionInline(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            expandedSource: """
                struct AppContainer {
                    var apiClient: APIClient {
                        get {
                            return _storage_apiClient
                        }
                    }

                    private let _storage_apiClient: APIClient
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required"),
                    message: "Concrete dependency 'apiClient: APIClient' requires concrete: true. Prefer protocol types when possible.",
                    line: 3,
                    column: 5,
                    notes: [
                        NoteSpec(
                            message: "If this dependency must remain a concrete type, opt in explicitly with concrete: true.",
                            line: 3,
                            column: 5
                        ),
                        NoteSpec(
                            message: "If protocol-first wiring is possible, prefer changing the property type to an existential such as any Protocol.",
                            line: 4,
                            column: 9
                        ),
                    ],
                    fixIts: [FixItSpec(message: "Add concrete: true")]
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Bare protocol type requires concrete opt-in for shared dependency")
    func bareProtocolSharedDependencyRequiresOptIn() {
        assertMacroExpansionInline(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClientProtocol
            }
            """,
            expandedSource: """
                struct AppContainer {
                    var apiClient: APIClientProtocol {
                        get {
                            return _storage_apiClient
                        }
                    }

                    private let _storage_apiClient: APIClientProtocol
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required"),
                    message: "Concrete dependency 'apiClient: APIClientProtocol' requires concrete: true. Prefer protocol types when possible.",
                    line: 3,
                    column: 5,
                    notes: [
                        NoteSpec(
                            message: "If this dependency must remain a concrete type, opt in explicitly with concrete: true.",
                            line: 3,
                            column: 5
                        ),
                        NoteSpec(
                            message: "If protocol-first wiring is possible, prefer changing the property type to an existential such as any Protocol.",
                            line: 4,
                            column: 9
                        ),
                    ],
                    fixIts: [FixItSpec(message: "Add concrete: true")]
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Bare optional protocol type requires concrete opt-in for shared dependency")
    func bareOptionalProtocolSharedDependencyRequiresOptIn() {
        assertMacroExpansionInline(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClientProtocol?
            }
            """,
            expandedSource: """
                struct AppContainer {
                    var apiClient: APIClientProtocol? {
                        get {
                            return _storage_apiClient
                        }
                    }

                    private let _storage_apiClient: APIClientProtocol?
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required"),
                    message: "Concrete dependency 'apiClient: APIClientProtocol?' requires concrete: true. Prefer protocol types when possible.",
                    line: 3,
                    column: 5,
                    notes: [
                        NoteSpec(
                            message: "If this dependency must remain a concrete type, opt in explicitly with concrete: true.",
                            line: 3,
                            column: 5
                        ),
                        NoteSpec(
                            message: "If protocol-first wiring is possible, prefer changing the property type to an existential such as any Protocol.",
                            line: 4,
                            column: 9
                        ),
                    ],
                    fixIts: [FixItSpec(message: "Add concrete: true")]
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Explicit any protocol shared dependency does not require concrete opt-in")
    func anyProtocolSharedDependencyDoesNotRequireOptIn() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: any APIClientProtocol
            }
            """,
            matches: "anyProtocolSharedDependency",
            macros: Self.macros
        )
    }

    @Test("Optional any protocol shared dependency does not require concrete opt-in")
    func optionalAnyProtocolSharedDependencyDoesNotRequireOptIn() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: (any APIClientProtocol)?
            }
            """,
            matches: "optionalAnyProtocolSharedDependency",
            macros: Self.macros
        )
    }

    @Test("Opaque some protocol shared dependency does not require concrete opt-in")
    func someProtocolSharedDependencyDoesNotRequireOptIn() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: some APIClientProtocol = APIClient()
            }
            """,
            matches: "someProtocolSharedDependency",
            macros: Self.macros
        )
    }

    @Test("Protocol composition shared dependency does not require concrete opt-in")
    func compositionSharedDependencyDoesNotRequireOptIn() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClientProtocol & LoggerProtocol
            }
            """,
            matches: "compositionSharedDependency",
            macros: Self.macros
        )
    }

    @Test
    func concreteSharedDependencyWithOptInGeneratesInit() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient(), concrete: true)
                var apiClient: APIClient
            }
            """,
            matches: "concreteSharedDependencyWithOptIn",
            macros: Self.macros
        )
    }

    @Test
    func validateFalseStillRejectsMissingSharedFactory() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(validate: false)
            struct AppContainer {
                @Provide(.shared)
                var service: any ServiceProtocol
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.shared-factory-required")
            ],
            macros: Self.macros
        )
    }

    @Test
    func validateFalseStillRejectsConcreteDependencyWithoutOptIn() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(validate: false)
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.concrete-opt-in-required")
            ],
            macros: Self.macros
        )
    }

    @Test
    func validateFalseStillRejectsInputFactory() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(validate: false)
            struct AppContainer {
                @Provide(.input, factory: Service())
                var service: any ServiceProtocol
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration")
            ],
            macros: Self.macros
        )
    }

    @Test("input scope rejects type-based dependency wiring")
    func inputScopeRejectsWithDependencies() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.input, APIClient.self, with: [\\.config])
                var apiClient: APIClient
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration"),
                MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference"),
            ],
            macros: Self.macros
        )
    }

    @Test
    func detectsContainerDependencyCycle() {
        assertMacroExpansionDiagnosticCodes(
            """
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
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.dependency-cycle")
            ],
            macros: Self.macros
        )
    }

    @Test
    func detectsUnknownDependencyInWithClause() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, APIClient.self, with: [\\.missing], concrete: true)
                var apiClient: APIClient
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")
            ],
            macros: Self.macros
        )
    }

    @Test
    func validateDAGFalseSkipsCycleValidation() {
        assertMacroExpansionSnapshot(
            """
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
            """,
            matches: "validateDAGFalseSkipsCycleValidation",
            macros: Self.macros
        )
    }

    @Test("String literal tokens do not trigger false dependency cycles")
    func stringLiteralTokensDoNotTriggerFalseDependencyCycles() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, concrete: true)
                var a: ServiceA = ServiceA(name: "b")

                @Provide(.shared, concrete: true)
                var b: ServiceB = ServiceB(name: "a")
            }
            """,
            matches: "stringLiteralTokensDoNotTriggerFalseDependencyCycles",
            macros: Self.macros
        )
    }

    @Test("mainActor: true annotates generated init with @MainActor")
    func mainActorContainerGeneratesMainActorInit() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input)
                var config: Config
            }
            """,
            matches: "mainActorContainerGeneratesMainActorInit",
            macros: Self.macros
        )
    }

    @Test("mainActor option conflicts with existing custom global actor")
    func mainActorConflictProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @FeatureActor
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input)
                var config: Config
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.mainactor-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("asyncFactory and factory cannot be used together")
    func asyncFactoryAndFactoryConflictProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Service(), asyncFactory: { () async in Service() }, concrete: true)
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("input scope rejects asyncFactory")
    func inputScopeRejectsAsyncFactory() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input, asyncFactory: { () async in Service() }, concrete: true)
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration"),
                MessageID(domain: "InnoDI.validation", id: "provide.async-factory-invalid-scope"),
            ],
            macros: Self.macros
        )
    }

    @Test("asyncFactory must be async closure")
    func asyncFactoryMustBeAsyncClosure() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { Service() }, concrete: true)
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.async-factory-must-be-async")
            ],
            macros: Self.macros
        )
    }

    @Test("async shared factory generates task-backed initialization")
    func asyncSharedFactoryGeneratesTaskBackedInit() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, asyncFactory: { (config: Config) async in Service(config: config) }, concrete: true)
                var service: Service
            }
            """,
            matches: "asyncSharedFactoryGeneratesTaskBackedInit",
            macros: Self.macros
        )
    }

    @Test("Factory parameter names must resolve by name without positional fallback")
    func factoryParameterNamesMustResolveStrictly() {
        assertMacroExpansionDiagnosticCodes(
            """
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
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
            ],
            macros: Self.macros
        )
    }

    @Test("Reordered factory parameters are allowed when names match")
    func reorderedFactoryParametersRemainValid() {
        assertMacroExpansionSnapshot(
            """
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
            """,
            matches: "reorderedFactoryParametersRemainValid",
            macros: Self.macros
        )
    }

    @Test("Sync shared dependencies cannot reference later shared members")
    func syncSharedDependenciesRejectForwardReferences() {
        assertMacroExpansionDiagnosticCodes(
            """
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
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
            ],
            macros: Self.macros
        )
    }

    @Test("with: dependencies reject later shared members")
    func withDependenciesRejectForwardReferences() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, Service.self, with: [\\.laterService], concrete: true)
                var service: Service

                @Provide(.shared, factory: LaterService(config: config), concrete: true)
                var laterService: LaterService
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
            ],
            macros: Self.macros
        )
    }

    @Test("Async shared dependencies cannot reference later async shared members")
    func asyncSharedDependenciesRejectForwardReferences() {
        assertMacroExpansionDiagnosticCodes(
            """
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
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
            ],
            macros: Self.macros
        )
    }

    @Test("Custom init inside container body is rejected explicitly")
    func customInitInsideContainerBodyIsRejected() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                init(config: Config) {
                    self.config = config
                }
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
            ],
            macros: Self.macros
        )
    }

    // NOTE: Tests involving same-file `extension AppContainer { init ... }` detection
    // continue to use the direct `DIContainerMacro.expansion(of:providingMembersOf:in:)`
    // call pattern. The `SwiftSyntaxMacroExpansion.expand()` pipeline detaches the
    // declaration from its parent chain, so the macro's `sourceFile(containing:)` walk
    // returns `nil` and sibling extensions are not discovered.
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
    func customInitInOtherSameFileExtensionDoesNotTriggerRejection() {
        assertMacroExpansionSnapshot(
            """
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
            """,
            matches: "customInitInOtherSameFileExtensionDoesNotTriggerRejection",
            macros: Self.macros
        )
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
    func genericArgumentExtensionsAreExcluded() {
        assertMacroExpansionSnapshot(
            """
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
            """,
            matches: "genericArgumentExtensionsAreExcluded",
            macros: Self.macros
        )
    }

    @Test("Constrained same-file extensions are excluded from custom init detection")
    func constrainedExtensionsAreExcluded() {
        assertMacroExpansionSnapshot(
            """
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
            """,
            matches: "constrainedExtensionsAreExcluded",
            macros: Self.macros
        )
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
