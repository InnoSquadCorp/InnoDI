import Foundation
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
        "InnoDI.DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "SubContainer": SubContainerMacro.self,
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
    func sharedMembersStillRequireFactories() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
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
    func concreteSharedDependenciesStillRequireExplicitOptIn() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
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
    func inputMembersStillRejectFactoryConfiguration() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
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

    @Test("Lazy<T> factory parameter breaks a two-shared cycle without restructuring")
    func lazyBreaksTwoCycleAcrossShared() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (b: Lazy<CoordinatorB>) in
                    CoordinatorA(b: b)
                }, concrete: true)
                var a: CoordinatorA

                @Provide(.shared, factory: { (a: CoordinatorA) in
                    CoordinatorB(a: a)
                }, concrete: true)
                var b: CoordinatorB
            }
            """,
            matches: "lazyBreaksTwoCycleAcrossShared",
            macros: Self.macros
        )
    }

    @Test("Qualified InnoDI.Lazy preserves the written wrapper qualifier")
    func qualifiedLazyBreaksTwoCycleAcrossShared() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (b: InnoDI.Lazy<CoordinatorB>) in
                    CoordinatorA(b: b)
                }, concrete: true)
                var a: CoordinatorA

                @Provide(.shared, factory: { (a: CoordinatorA) in
                    CoordinatorB(a: a)
                }, concrete: true)
                var b: CoordinatorB
            }
            """,
            matches: "qualifiedLazyBreaksTwoCycleAcrossShared",
            macros: Self.macros
        )
    }

    @Test("Lazy<T> breaks a three-shared cycle as long as at least one edge is soft")
    func lazyBreaksThreeCycle() {
        // Cycle: a → c (soft), c → b (hard), b → a (hard). The soft edge on
        // `a` makes the hard-only adjacency a linear chain b→a, c→b, so
        // cycle detection passes while declaration-order availability still
        // holds for every hard reference.
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (c: Lazy<C>) in
                    A(c: c)
                }, concrete: true)
                var a: A

                @Provide(.shared, factory: { (a: A) in
                    B(a: a)
                }, concrete: true)
                var b: B

                @Provide(.shared, factory: { (b: B) in
                    C(b: b)
                }, concrete: true)
                var c: C
            }
            """,
            matches: "lazyBreaksThreeCycle",
            macros: Self.macros
        )
    }

    @Test("Lazy<T> can target a transient dependency through a late-bound resolver")
    func lazyTargetsTransientDependency() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (service: Lazy<Service>) in
                    Holder(service: service)
                }, concrete: true)
                var holder: Holder

                @Provide(.transient, factory: { Service() }, concrete: true)
                var service: Service
            }
            """,
            matches: "lazyTargetsTransientDependency",
            macros: Self.macros
        )
    }

    @Test("Lazy<T> rejects async shared targets with a source diagnostic")
    func lazyCannotTargetAsyncSharedDependency() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (serviceB: Lazy<ServiceB>) in
                    ServiceA(serviceB: serviceB)
                }, concrete: true)
                var serviceA: ServiceA

                @Provide(.shared, asyncFactory: { () async in
                    ServiceB()
                }, concrete: true)
                var serviceB: ServiceB
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-unsupported-target")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T> factory parameter wires a shared factory to a transient target")
    func providerInSharedFactoryInjectsFreshTransient() {
        // `.shared` factory receives a Provider<Request>. Generated code
        // should declare `_lazyCell_request` (reusing the Lazy cell
        // infrastructure), bind `_lazyCell_request.bindResolver { _lazySelf.request }`
        // after init, and pass `Provider({ _lazyCell_request.resolve() })` to
        // the factory. The snapshot captures the full init body.
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, factory: { (config: Config) in
                    Request(config: config)
                }, concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(requests: request)
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            matches: "providerInSharedFactoryInjectsFreshTransient",
            macros: Self.macros
        )
    }

    @Test("Provider<T> factory parameter works in a transient accessor (no init box needed)")
    func providerInTransientAccessorFactory() {
        // Transient-in-transient Provider: the processor's factory receives
        // `Provider<Payload>` and should be wrapped via a short-lived
        // `_resolverCell` so the generated `@Sendable` resolver never
        // captures `self` directly.
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var input: PayloadInput

                @Provide(.transient, factory: { (input: PayloadInput) in
                    Payload(input: input)
                }, concrete: true)
                var payload: Payload

                @Provide(.transient, factory: { (payload: Provider<Payload>) in
                    PayloadProcessor(payloads: payload)
                }, concrete: true)
                var processor: PayloadProcessor
            }
            """,
            matches: "providerInTransientAccessorFactory",
            macros: Self.macros
        )
    }

    @Test("Provider<T> against a non-transient target emits a diagnostic")
    func providerOnNonTransientTargetFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service(), concrete: true)
                var service: Service

                @Provide(.shared, factory: { (service: Provider<Service>) in
                    Consumer(service: service)
                }, concrete: true)
                var consumer: Consumer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-non-transient-target")
            ],
            macros: Self.macros
        )

        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var service: Service

                @Provide(.shared, factory: { (service: Provider<Service>) in
                    Consumer(service: service)
                }, concrete: true)
                var consumer: Consumer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-non-transient-target")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T> rejects async transient targets")
    func providerOnAsyncTransientTargetFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async in
                    Request()
                }, concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request)
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-unsupported-target")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T> rejects async throwing transient targets")
    func providerOnAsyncThrowingTransientTargetFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, asyncFactory: { () async throws -> Request in
                    Request()
                }, concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request)
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-unsupported-target")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T> forward reference does not count as a cycle or unavailable edge")
    func providerDoesNotCountAsCycle() {
        // `logger` declared before `request` and references it forward via
        // Provider — hard-only adjacency is empty on that edge, so no cycle
        // and no `provide.unavailable-dependency-reference`.
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(requests: request)
                }, concrete: true)
                var logger: RequestLogger

                @Provide(.transient, factory: { (config: Config) in
                    Request(config: config)
                }, concrete: true)
                var request: Request
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("Provider<T> cannot be called directly inside a shared factory body")
    func providerDirectCallInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request())
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T>.callAsFunction() is also rejected inside a shared factory body")
    func providerCallAsFunctionInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request.callAsFunction())
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Parenthesized Provider<T> calls are rejected inside a shared factory body")
    func providerParenthesizedCallInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: (request)())
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Resolver-style Provider<T> calls are rejected inside a shared factory body")
    func providerResolverCallInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request.resolver())
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T> cannot be called directly inside an async shared factory body")
    func providerDirectCallInsideAsyncSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.shared, asyncFactory: { (request: Provider<Request>) async in
                    AsyncLogger(request: request())
                }, concrete: true)
                var logger: AsyncLogger
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.provider-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Provider<T> direct calls remain allowed in transient factories")
    func providerDirectCallInsideTransientFactoryRemainsAllowed() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: Request(), concrete: true)
                var request: Request

                @Provide(.transient, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request())
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("Qualified InnoDI.Provider preserves the written wrapper qualifier")
    func qualifiedProviderInSharedFactory() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, factory: { (config: Config) in
                    Request(config: config)
                }, concrete: true)
                var request: Request

                @Provide(.shared, factory: { (request: InnoDI.Provider<Request>) in
                    RequestLogger(requests: request)
                }, concrete: true)
                var logger: RequestLogger
            }
            """,
            matches: "qualifiedProviderInSharedFactory",
            macros: Self.macros
        )
    }

    @Test("Cycle without Lazy still fails validation with the Lazy hint")
    func cycleWithoutLazyStillFails() {
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

    @Test("validateDAG: false still expands graph-derived misses through runtime fallback")
    func validateDAGFalseSkipsGraphDerivedDependencyDiagnostics() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.shared, factory: { (laterService: LaterService, missing: MissingService) in
                    Service(laterService: laterService, missing: missing)
                }, concrete: true)
                var service: Service

                @Provide(.shared, factory: LaterService(), concrete: true)
                var laterService: LaterService
            }
            """,
            matches: "validateDAGFalseSkipsGraphDerivedDependencyDiagnostics",
            macros: Self.macros
        )
    }

    @Test("validateDAG: false still expands type-based wiring through runtime fallback")
    func validateDAGFalseSkipsWithDependencyDiagnostics() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.shared, Service.self, with: [\\.laterService, \\.missingService], concrete: true)
                var service: Service

                @Provide(.shared, factory: LaterService(), concrete: true)
                var laterService: LaterService
            }
            """,
            matches: "validateDAGFalseSkipsWithDependencyDiagnostics",
            macros: Self.macros
        )
    }

    @Test("validateDAG: false with: expansion still typechecks after fallback rewrites")
    func validateDAGFalseWithDependencyFallbackExpansionTypechecks() throws {
        try assertExpandedSourceTypechecks(
            """
            struct LaterService {}
            struct MissingService {}
            struct Service {
                init(laterService: LaterService, missingService: MissingService) {}
            }

            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.shared, Service.self, with: [\\.laterService, \\.missingService], concrete: true)
                var service: Service

                @Provide(.shared, factory: LaterService(), concrete: true)
                var laterService: LaterService
            }
            """,
            macros: Self.macros
        )
    }

    @Test("validateDAG: false still diagnoses raw-expression declaration-order misses")
    func validateDAGFalseStillDiagnosesRawExpressionReferences() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct LaterService {}
            struct Service {
                init(laterService: LaterService) {}
            }

            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.shared, factory: Service(laterService: laterService), concrete: true)
                var service: Service

                @Provide(.shared, factory: LaterService(), concrete: true)
                var laterService: LaterService
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
            ],
            macros: Self.macros
        )
    }

    @Test("validateDAG: false still preserves structural diagnostics")
    func validateDAGFalseStillPreservesStructuralDiagnostics() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.input, factory: Service())
                var service: Service
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration")
            ],
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

    @Test("mainActor: true propagates to transient sub-container accessors and build closures")
    func mainActorTransientSubContainerUsesSendableBuildClosure() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input) var config: Config

                @SubContainer(scope: .transient)
                var feature: FeatureContainer
            }
            """,
            matches: "mainActorTransientSubContainerUsesSendableBuildClosure",
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

    @Test("mainActor option conflicts with existing qualified custom global actor")
    func mainActorConflictWithQualifiedActorProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @FeatureKit.FeatureActor
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

    @Test("mainActor option conflicts with existing qualified custom global actor on qualified DIContainer")
    func mainActorConflictWithQualifiedActorAndQualifiedContainerProducesDiagnostic() throws {
        let source = """
        @FeatureKit.FeatureActor
        @InnoDI.DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.last?.as(AttributeSyntax.self) else {
            Issue.record("Should parse qualified DIContainer declaration")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.mainactor-conflict")
        })
        #expect(context.diagnostics.contains {
            $0.message.contains("@FeatureKit.FeatureActor")
        })
    }

    @Test("qualified DIContainer with mainActor true remains allowed without custom actor")
    func qualifiedDIContainerMainActorRemainsAllowedWithoutConflict() throws {
        let source = """
        @InnoDI.DIContainer(mainActor: true)
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse qualified DIContainer declaration without custom actor")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(context.diagnostics.isEmpty)
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

    @Test("Factory parameter diagnostics suppress fix-its for declaration-order unavailable shared candidates")
    func unresolvedFactoryParameterDiagnosticsSkipUnavailableFixItForSharedMember() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (later_service: LaterService) in
                Service(laterService: later_service)
            }, concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse declaration-order unresolved factory parameter fixture")
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
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains(where: { $0.message.contains("declaration order") }))
    }

    @Test("Factory parameter diagnostics keep fix-its for async shared members that can see later sync shared dependencies")
    func unresolvedFactoryParameterDiagnosticsIncludeFixItForAsyncSharedLaterSyncDependency() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, asyncFactory: { (later_service: LaterService) async in
                Service(laterService: later_service)
            }, concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse async shared unresolved factory parameter fixture")
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
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("laterService") == true)
    }

    @Test("Factory parameter diagnostics keep fix-its for transient members that can see later dependencies")
    func unresolvedFactoryParameterDiagnosticsIncludeFixItForTransientLaterDependency() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.transient, factory: { (later_service: LaterService) in
                Service(laterService: later_service)
            }, concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse transient unresolved factory parameter fixture")
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
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("laterService") == true)
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

    @Test("with dependency diagnostics suppress fix-its for declaration-order unavailable shared candidates")
    func unresolvedWithDependencyDiagnosticsSkipUnavailableFixItForSharedMember() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, Service.self, with: [\\.later_service], concrete: true)
            var service: Service

            @Provide(.shared, factory: LaterService(), concrete: true)
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse declaration-order unresolved with dependency fixture")
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
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains(where: { $0.message.contains("declaration order") }))
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

    // MARK: - Phase M: @SubContainer

    @Test("`.shared` sub-container auto-matches parent members into the child init")
    func subContainerSharedAutoMatch() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerSharedAutoMatch",
            macros: Self.macros
        )
    }

    @Test("`.transient` sub-container binds a build closure captured from a self snapshot")
    func subContainerTransientBuildsFreshChild() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .transient)
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerTransientBuildsFreshChild",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports explicit child/parent input remapping via bindings:")
    func subContainerSharedExplicitBindings() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            matches: "subContainerSharedExplicitBindings",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports multiple bindings remapping different child/parent pairs")
    func subContainerSharedBindingsMultipleRemaps() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.input) var apiService: any APIClientProtocol
                @Provide(.shared, factory: Logger(), concrete: true) var logger: Logger

                @SubContainer(
                    scope: .shared,
                    bindings: [
                        (child: \\.featureConfig, parent: \\.config),
                        (child: \\.apiClient, parent: \\.apiService),
                        (child: \\.featureLogger, parent: \\.logger)
                    ]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            matches: "subContainerSharedBindingsMultipleRemaps",
            macros: Self.macros
        )
    }

    @Test("`.transient` sub-container supports explicit child/parent input remapping via bindings:")
    func subContainerTransientExplicitBindings() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .transient,
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            matches: "subContainerTransientExplicitBindings",
            macros: Self.macros
        )
    }

    @Test("Container with only @SubContainer still generates init and Overrides")
    func subContainerOnlyParentGeneratesInitAndOverrides() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerOnlyParentGeneratesInitAndOverrides",
            macros: Self.macros
        )
    }

    @Test("@SubContainer with both with: and bindings: emits sub.bindings-conflicts-with-with")
    func subContainerBindingsConflictWithWithDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.config],
                    bindings: [(child: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.bindings-conflicts-with-with")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer duplicate child bindings emit sub.duplicate-child-binding")
    func subContainerDuplicateChildBindingDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.input) var fallbackConfig: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [
                        (child: \\.featureConfig, parent: \\.config),
                        (child: \\.featureConfig, parent: \\.fallbackConfig)
                    ]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.duplicate-child-binding")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer multi-binding emits sub.single-binding")
    func subContainerSingleBindingDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var first, second: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "SwiftSyntaxMacroExpansion", id: "accessorMacroOnVariableWithMultipleBindings"),
                MessageID(domain: "SwiftSyntaxMacroExpansion", id: "peerMacroOnVariableWithMultipleBindings"),
                MessageID(domain: "InnoDI.usage", id: "sub.single-binding")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: with an unknown parent member emits sub.unknown-parent-member")
    func subContainerBindingsUnknownParentMemberDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureConfig, parent: \\.missing)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer wildcard binding emits sub.named-property-required")
    func subContainerNamedPropertyRequiredDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var _: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "sub.named-property-required")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer inferred type emits sub.explicit-type-required")
    func subContainerExplicitTypeRequiredDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature = FeatureContainer()
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "sub.explicit-type-required")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer without scope: emits sub.scope-required")
    func subContainerMissingScopeDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer()
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.scope-required")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer unknown scope anchors the diagnostic to the scope expression")
    func subContainerUnknownScopeAnchorsToScopeExpression() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .request
                )
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerUnknownScopeAnchorsToScopeExpression",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "sub.unknown-scope"),
                    message: "Unknown @SubContainer scope '.request' on 'feature'. Valid scopes are .shared and .transient.",
                    line: 6,
                    column: 16
                )
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with unknown scope value emits sub.unknown-scope")
    func subContainerUnknownScopeDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .request)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.unknown-scope")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with unknown parent member anchors the diagnostic to the keypath")
    func subContainerUnknownParentMemberAnchorsToKeyPath() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.missing]
                )
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerUnknownParentMemberAnchorsToKeyPath",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member"),
                    message: "@SubContainer on 'feature' references parent member 'missing' via with:, but no such member exists. Only @Provide-annotated parent members can be passed to a child container.",
                    line: 7,
                    column: 16
                )
            ],
            macros: Self.macros
        )
    }

    @Test("@Provide + @SubContainer on the same property emits sub.conflicts-with-provide")
    func subContainerConflictsWithProvideDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(.shared, factory: FeatureContainer(config: config), concrete: true)
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.conflicts-with-provide")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with transient parent in with: anchors the diagnostic to the keypath")
    func subContainerTransientParentAnchorUsesKeyPath() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.transient, factory: Request(), concrete: true) var request: Request

                @SubContainer(
                    scope: .shared,
                    with: [\\.request]
                )
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerTransientParentAnchorUsesKeyPath",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient"),
                    message: "@SubContainer(scope: .shared) 'feature' cannot read parent member 'request' because it has .transient scope — the child is built inside init where transient accessors are not yet callable. Use @SubContainer(scope: .transient) instead, or restructure the parent so 'request' is .shared or .input.",
                    line: 8,
                    column: 16
                )
            ],
            macros: Self.macros
        )
    }

    @Test("`with: [\\.unknown]` emits sub.unknown-parent-member")
    func subContainerUnknownParentMemberDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.nonexistent])
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.unknown-parent-member")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer generated override slot names diagnose member collisions")
    func subContainerOverrideNameConflictDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var featureOverrides: String

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.overrides-name-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("`.shared` sub reading a `.transient` parent member emits sub.shared-parent-must-not-be-transient")
    func subContainerSharedParentMustNotBeTransientDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(.transient, factory: { (config: AppConfig) in Request(config: config) }, concrete: true)
                var request: Request

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient")
            ],
            macros: Self.macros
        )
    }

    @Test("`.shared` sub bindings: must not target a `.transient` parent member")
    func subContainerBindingsSharedParentMustNotBeTransientDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(.transient, factory: { (config: AppConfig) in Request(config: config) }, concrete: true)
                var request: Request

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureRequest, parent: \\.request)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient")
            ],
            macros: Self.macros
        )
    }

    @Test("Sub-container-only containers still diagnose nested Overrides conflicts")
    func subContainerOnlyParentStillDiagnosesOverridesConflict() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature: FeatureContainer

                struct Overrides {}
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.overrides-name-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("Sub-container targeting an input-only child still expands without warnings")
    func subContainerTargetingInputOnlyChildDoesNotWarn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: AppConfig

            @SubContainer(scope: .shared)
            var feature: FeatureContainer
        }

        @DIContainer
        struct FeatureContainer {
            @Provide(.input) var config: AppConfig
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with sibling FeatureContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(context.diagnostics.isEmpty)
        #expect(!generated.isEmpty)
    }

    // Phase N-4 — `provide.lazy-aliased` / `provide.provider-aliased` warn
    // when a closure parameter uses a typealias that aliases `Lazy<T>` /
    // `Provider<T>`.
    @Test("Closure parameter using a Lazy typealias emits the lazy-aliased warning")
    func lazyAliasedParameterWarns() throws {
        let source = """
        struct Config {}
        typealias SomeLazy<T> = InnoDI.Lazy<T>

        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: Config(), concrete: true)
            var config: Config

            @Provide(.shared, factory: { (config: SomeLazy<Config>) in Service(config: config) }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: {
                  $0.item.as(StructDeclSyntax.self)?.name.text == "AppContainer"
              })?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with sibling typealias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let expectedID = MessageID(
            domain: "InnoDI.validation",
            id: "provide.lazy-aliased"
        )
        #expect(context.diagnostics.count == 1)
        #expect(context.diagnostics.first?.diagnosticID == expectedID)
    }

    @Test("Non-generic typealias for Lazy also emits the lazy-aliased warning")
    func nonGenericLazyAliasParameterWarns() throws {
        let source = """
        struct Foo {}
        typealias FooLazy = InnoDI.Lazy<Foo>

        @DIContainer
        struct AppContainer {
            @Provide(.input) var foo: Foo
            @Provide(.shared, factory: { (foo: FooLazy) in Service(fooProvider: foo) }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: {
                  $0.item.as(StructDeclSyntax.self)?.name.text == "AppContainer"
              })?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with non-generic FooLazy alias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let expectedID = MessageID(
            domain: "InnoDI.validation",
            id: "provide.lazy-aliased"
        )
        #expect(context.diagnostics.count == 1)
        #expect(context.diagnostics.first?.diagnosticID == expectedID)
    }

    @Test("Closure parameter using a Provider typealias emits the provider-aliased warning")
    func providerAliasedParameterWarns() throws {
        let source = """
        struct Config {}
        typealias SomeProvider<T> = InnoDI.Provider<T>

        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: Config

            @Provide(.transient, factory: { (config: Config) in
                Request(config: config)
            }, concrete: true)
            var request: Request

            @Provide(.transient, factory: { (request: SomeProvider<Request>) in
                RequestLogger(provider: request)
            }, concrete: true)
            var logger: RequestLogger
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: {
                  $0.item.as(StructDeclSyntax.self)?.name.text == "AppContainer"
              })?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with sibling typealias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let expectedID = MessageID(
            domain: "InnoDI.validation",
            id: "provide.provider-aliased"
        )
        #expect(context.diagnostics.count == 1)
        #expect(context.diagnostics.first?.diagnosticID == expectedID)
    }

    @Test("Unrelated typealiases do not trigger the aliased warning")
    func unrelatedTypealiasDoesNotWarn() throws {
        let source = """
        typealias UserID = Int

        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: AppConfig
            @Provide(.shared, factory: { (config: AppConfig) in Service(config: config) }, concrete: true)
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: { $0.item.is(StructDeclSyntax.self) })?
                .item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with unrelated typealias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(context.diagnostics.isEmpty)
    }

}

private func assertExpandedSourceTypechecks(
    _ originalSource: String,
    macros: [String: any Macro.Type],
    testModuleName: String = "TestModule",
    testFileName: String = "test.swift",
    indentationWidth: Trivia = .spaces(4),
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) throws {
    let sourceLocation = Testing.SourceLocation(
        fileID: "\(fileID)",
        filePath: "\(filePath)",
        line: Int(line),
        column: Int(column)
    )

    let expansionResult = expandMacroSource(
        originalSource,
        macros: macros,
        testModuleName: testModuleName,
        testFileName: testFileName,
        indentationWidth: indentationWidth
    )

    if !expansionResult.diagnostics.isEmpty {
        let debug = expansionResult.diagnostics.map(\.debugDescription).joined(separator: "\n")
        Issue.record(
            Comment(rawValue: "Expected zero macro diagnostics before typechecking expanded source:\n\(debug)"),
            sourceLocation: sourceLocation
        )
        return
    }

    let fixtureDirectoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("InnoDI-Macro-Typecheck-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: fixtureDirectoryURL) }

    try FileManager.default.createDirectory(at: fixtureDirectoryURL, withIntermediateDirectories: true)

    let fixtureURL = fixtureDirectoryURL.appendingPathComponent(testFileName)
    let stdoutURL = fixtureDirectoryURL.appendingPathComponent("stdout.txt")
    let stderrURL = fixtureDirectoryURL.appendingPathComponent("stderr.txt")

    try expansionResult.expansion.write(to: fixtureURL, atomically: true, encoding: .utf8)
    FileManager.default.createFile(atPath: stdoutURL.path(percentEncoded: false), contents: Data())
    FileManager.default.createFile(atPath: stderrURL.path(percentEncoded: false), contents: Data())

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swiftc", "-typecheck", fixtureURL.path(percentEncoded: false)]

    let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
    let stderrHandle = try FileHandle(forWritingTo: stderrURL)
    defer {
        stdoutHandle.closeFile()
        stderrHandle.closeFile()
    }
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle

    try process.run()
    process.waitUntilExit()

    let stdout = String(decoding: (try? Data(contentsOf: stdoutURL)) ?? Data(), as: UTF8.self)
    let stderr = String(decoding: (try? Data(contentsOf: stderrURL)) ?? Data(), as: UTF8.self)

    if process.terminationStatus != 0 {
        let message = """
            Expanded source failed to typecheck.
            Exit code: \(process.terminationStatus)
            stdout:
            \(stdout)
            stderr:
            \(stderr)

            Expanded source:
            \(expansionResult.expansion)
            """
        Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
    }
}
