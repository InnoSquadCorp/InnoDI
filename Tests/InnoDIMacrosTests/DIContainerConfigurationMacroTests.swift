import Foundation
import InnoDICore
import InnoDITestSupport
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

extension DIContainerMacroTests {
    @Test("DIContainer Bool options must be literals")
    func containerBoolOptionsRequireLiterals() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(root: isRoot, validateDAG: !FAST_BUILD, mainActor: Flags.mainActor)
            struct AppContainer {
                @Provide(.input)
                var config: Config
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.bool-literal-required"),
                MessageID(domain: "InnoDI.validation", id: "container.bool-literal-required"),
                MessageID(domain: "InnoDI.validation", id: "container.bool-literal-required"),
            ],
            macros: Self.macros
        )
    }

    @Test("@Provide with: requires a literal key-path array")
    func provideWithRequiresLiteralKeyPathArray() {
        assertMacroExpansionDiagnosticCodes(
            """
            let dependencies = [\\AppContainer.config]

            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, Service.self, with: dependencies)
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.invalid-with-dependencies")
            ],
            macros: Self.macros
        )
    }

    @Test("@Provide with: rejects malformed literal array elements")
    func provideWithRejectsMalformedLiteralArrayElements() {
        assertMacroExpansionDiagnosticCodes(
            """
            func makeKeyPath() -> Any { fatalError() }

            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, Service.self, with: [\\Self.config, makeKeyPath()])
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.invalid-with-dependencies")
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
                @Provide(.transient, factory: Service(), asyncFactory: { () async in Service() })
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider construction sources are mutually exclusive")
    func providerConstructionSourcesAreMutuallyExclusive() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(
                    .shared,
                    Service.self,
                    factory: Service(),
                )
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.construction-source-conflict"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("with wiring is exclusive to Type.self construction")
    func withWiringRequiresTypeConstruction() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(
                    .shared,
                    with: [\\Self.config],
                    factory: { (config: Config) in Service(config: config) },
                )
                var factoryService: Service

                @Provide(.shared, with: [\\Self.config])
                var initializedService: Service = Service(config: Config())
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.with-requires-type-construction"
                ),
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.with-requires-type-construction"
                ),
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
                @Provide(.input, asyncFactory: { () async in Service() })
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
                @Provide(.transient, asyncFactory: { Service() })
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.async-factory-must-be-async")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects async closure")
    func syncFactoryRejectsAsyncClosure() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { () async in Service() })
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-be-sync")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects throwing closure")
    func syncFactoryRejectsThrowingClosure() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { () throws in Service() })
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-not-throw")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects inferred throwing closure body")
    func syncFactoryRejectsInferredThrowingClosureBody() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { try makeService() })
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-not-throw")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects throwing expression factory")
    func syncFactoryRejectsThrowingExpressionFactory() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: try makeService())
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-not-throw")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects inferred async closure body")
    func syncFactoryRejectsInferredAsyncClosureBody() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { await makeService() })
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-be-sync")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory allows nonthrowing try variants")
    func syncFactoryAllowsNonthrowingTryVariants() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { try? makeService() })
                var optionalService: Service?

                @Provide(.transient, factory: { try! makeRequiredService() })
                var requiredService: Service
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("sync factory allows handled throwing closure body")
    func syncFactoryAllowsHandledThrowingClosureBody() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(
                    .transient,
                    factory: {
                        do {
                            return try makeService()
                        } catch {
                            return fallbackService()
                        }
                    },
                )
                var service: Service
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects throwing catch handler body")
    func syncFactoryRejectsThrowingCatchHandlerBody() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(
                    .transient,
                    factory: {
                        do {
                            return try makeService()
                        } catch {
                            return try fallbackService()
                        }
                    },
                )
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-not-throw")
            ],
            macros: Self.macros
        )
    }

    @Test("sync factory rejects throwing body with nonexhaustive catch")
    func syncFactoryRejectsThrowingBodyWithNonexhaustiveCatch() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(
                    .transient,
                    factory: {
                        do {
                            return try makeService()
                        } catch let error as ServiceError {
                            return fallbackService(error)
                        }
                    },
                )
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.factory-must-not-throw")
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

                @Provide(.shared, asyncFactory: { (config: Config) async in Service(config: config) })
                var service: Service
            }
            """,
            matches: "asyncSharedFactoryGeneratesTaskBackedInit",
            macros: Self.macros
        )
    }

    @Test("async factories do not synthesize unused resolved input locals")
    func asyncFactoryWithoutDependenciesSkipsResolvedLocals() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, factory: Logger())
                var logger: Logger

                @Provide(.shared, asyncFactory: { () async in Service() })
                var service: Service
            }
            """,
            matches: "asyncFactoryWithoutDependenciesSkipsResolvedLocals",
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
                })
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
                })
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
                })
                var service: Service

                @Provide(.shared, factory: { (config: Config) in
                    LaterService(config: config)
                })
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

                @Provide(.shared, Service.self, with: [\\Self.laterService])
                var service: Service

                @Provide(.shared, factory: { (config: Config) in
                    LaterService(config: config)
                })
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
                })
                var service: Service

                @Provide(.shared, asyncFactory: { (config: Config) async in
                    LaterService(config: config)
                })
                var laterService: LaterService
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
            ],
            macros: Self.macros
        )
    }

}
