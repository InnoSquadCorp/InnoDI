import Foundation
import InnoDICore
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
        "DIComponent": DIComponentMacro.self,
        "DIHierarchyRoot": DIHierarchyRootMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "InnoDI._InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
    ]

    @Test("A flagless concrete shared dependency keeps its declared storage type")
    func flaglessConcreteSharedDependencyGeneratesStorage() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var apiClient: APIClient"))
        #expect(result.expansion.contains("init(apiClient: APIClient? = nil)"))
        #expect(result.expansion.contains("self._storage_apiClient = apiClient ?? APIClient()"))
    }

    @Test("A flagless concrete transient dependency keeps its declared override type")
    func flaglessConcreteTransientDependencyGeneratesOverride() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var apiClient: APIClient"))
        #expect(result.expansion.contains("init(apiClient: APIClient? = nil)"))
        #expect(result.expansion.contains("self._override_apiClient = apiClient"))
    }

    @Test("A flagless optional concrete dependency keeps its declared optional type")
    func flaglessOptionalConcreteDependencyGeneratesStorage() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient?
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var apiClient: APIClient?"))
        #expect(result.expansion.contains("self._storage_apiClient = apiClient ?? APIClient()"))
    }

    @Test("Explicit any protocol shared dependency keeps existential storage")
    func anyProtocolSharedDependencyKeepsExistentialStorage() {
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

    @Test("Optional any protocol shared dependency keeps optional existential storage")
    func optionalAnyProtocolSharedDependencyKeepsOptionalExistentialStorage() {
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

    @Test("Opaque some protocol provider types are rejected")
    func someProtocolProviderTypeIsRejected() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared)
                var apiClient: some APIClientProtocol = APIClient()
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "provide.opaque-type-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Protocol composition shared dependency keeps composition storage")
    func compositionSharedDependencyKeepsCompositionStorage() {
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

    @Test("package containers propagate package access to generated APIs")
    func packageContainerGeneratesPackageAPIs() {
        assertMacroExpansionInline(
            """
            @DIContainer
            package struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            expandedSource: """
                package struct AppContainer {
                    @InnoDI._InnoDIProvideAccessor(recovery: false)
                    var apiClient: APIClient

                    // MARK: - Initialization
                    package init(apiClient: APIClient? = nil) {
                        self._storage_apiClient = apiClient ?? APIClient()
                    }

                    // MARK: - Overrides Builder
                    package struct Overrides {
                        package var apiClient: APIClient? = nil
                    }

                    package typealias _InnoDIMountOverrides = Overrides

                    // MARK: - Convenience Init with Overrides
                    package init(_ _innoDIApplyOverrides: (inout Overrides) -> Void) {
                        var _innoDIOverrides = Self.Overrides()
                        _innoDIApplyOverrides(&_innoDIOverrides)
                        self.init(apiClient: _innoDIOverrides.apiClient)
                    }

                    // MARK: - withOverrides
                    package static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (throws)
                    package static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return try _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (async)
                    package nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return await _innoDIOperation(_innoDIContainer)
                    }

                    // MARK: - withOverrides (async throws)
                    package nonisolated(nonsending) static func withOverrides<OperationResult>(_ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
                        let _innoDIContainer = Self(_innoDIApplyOverrides)
                        return try await _innoDIOperation(_innoDIContainer)
                    }
                }
                """,
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

                @Provide(.input, APIClient.self, with: [\\Self.config])
                var apiClient: APIClient
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "provide.input-invalid-configuration"),
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
                })
                var serviceA: ServiceA

                @Provide(.transient, factory: { (serviceA: ServiceA) in
                    ServiceB(serviceA: serviceA)
                })
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

                @Provide(.shared, APIClient.self, with: [\\Self.missing])
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
                })
                var a: CoordinatorA

                @Provide(.shared, factory: { (a: CoordinatorA) in
                    CoordinatorB(a: a)
                })
                var b: CoordinatorB
            }
            """,
            matches: "lazyBreaksTwoCycleAcrossShared",
            macros: Self.macros
        )
    }

    @Test("Qualified InnoDI.Lazy uses shadow-safe contextual construction")
    func qualifiedLazyBreaksTwoCycleAcrossShared() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: { (b: InnoDI.Lazy<CoordinatorB>) in
                    CoordinatorA(b: b)
                })
                var a: CoordinatorA

                @Provide(.shared, factory: { (a: CoordinatorA) in
                    CoordinatorB(a: a)
                })
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
                })
                var a: A

                @Provide(.shared, factory: { (a: A) in
                    B(a: a)
                })
                var b: B

                @Provide(.shared, factory: { (b: B) in
                    C(b: b)
                })
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
                })
                var holder: Holder

                @Provide(.transient, factory: { Service() })
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
                })
                var serviceA: ServiceA

                @Provide(.shared, asyncFactory: { () async in
                    ServiceB()
                })
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
                })
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(requests: request)
                })
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
                })
                var payload: Payload

                @Provide(.transient, factory: { (payload: Provider<Payload>) in
                    PayloadProcessor(payloads: payload)
                })
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
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.shared, factory: { (service: Provider<Service>) in
                    Consumer(service: service)
                })
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
                })
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
                })
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request)
                })
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
                })
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request)
                })
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
                })
                var logger: RequestLogger

                @Provide(.transient, factory: { (config: Config) in
                    Request(config: config)
                })
                var request: Request
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("Lazy<T> cannot be called directly inside a shared factory body")
    func lazyDirectCallInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.shared, factory: { (service: Lazy<Service>) in
                    ServiceHolder(service: service())
                })
                var holder: ServiceHolder
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Lazy<T>.callAsFunction() is also rejected inside a shared factory body")
    func lazyCallAsFunctionInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.shared, factory: { (service: Lazy<Service>) in
                    ServiceHolder(service: service.callAsFunction())
                })
                var holder: ServiceHolder
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Parenthesized Lazy<T> calls are rejected inside a shared factory body")
    func lazyParenthesizedCallInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.shared, factory: { (service: Lazy<Service>) in
                    ServiceHolder(service: (service)())
                })
                var holder: ServiceHolder
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Resolver-style Lazy<T> calls are rejected inside a shared factory body")
    func lazyResolverCallInsideSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.shared, factory: { (service: Lazy<Service>) in
                    ServiceHolder(service: service.resolver())
                })
                var holder: ServiceHolder
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Lazy<T> cannot be called directly inside an async shared factory body")
    func lazyDirectCallInsideAsyncSharedFactoryFails() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.shared, asyncFactory: { (service: Lazy<Service>) async in
                    AsyncHolder(service: service())
                })
                var holder: AsyncHolder
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "provide.lazy-eager-call")
            ],
            macros: Self.macros
        )
    }

    @Test("Lazy<T> direct calls remain allowed in transient factories")
    func lazyDirectCallInsideTransientFactoryRemainsAllowed() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: Service())
                var service: Service

                @Provide(.transient, factory: { (service: Lazy<Service>) in
                    ServiceHolder(service: service())
                })
                var holder: ServiceHolder
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
                @Provide(.transient, factory: Request())
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request())
                })
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
                @Provide(.transient, factory: Request())
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request.callAsFunction())
                })
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
                @Provide(.transient, factory: Request())
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: (request)())
                })
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
                @Provide(.transient, factory: Request())
                var request: Request

                @Provide(.shared, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request.resolver())
                })
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
                @Provide(.transient, factory: Request())
                var request: Request

                @Provide(.shared, asyncFactory: { (request: Provider<Request>) async in
                    AsyncLogger(request: request())
                })
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
                @Provide(.transient, factory: Request())
                var request: Request

                @Provide(.transient, factory: { (request: Provider<Request>) in
                    RequestLogger(request: request())
                })
                var logger: RequestLogger
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("Qualified InnoDI.Provider uses shadow-safe contextual construction")
    func qualifiedProviderInSharedFactory() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, factory: { (config: Config) in
                    Request(config: config)
                })
                var request: Request

                @Provide(.shared, factory: { (request: InnoDI.Provider<Request>) in
                    RequestLogger(requests: request)
                })
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
                })
                var serviceA: ServiceA

                @Provide(.transient, factory: { (serviceA: ServiceA) in
                    ServiceB(serviceA: serviceA)
                })
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
                })
                var serviceA: ServiceA

                @Provide(.transient, factory: { (serviceA: ServiceA) in
                    ServiceB(serviceA: serviceA)
                })
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
                })
                var service: Service

                @Provide(.shared, factory: LaterService())
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
                @Provide(.shared, Service.self, with: [\\Self.laterService, \\Self.missingService])
                var service: Service

                @Provide(.shared, factory: LaterService())
                var laterService: LaterService
            }
            """,
            matches: "validateDAGFalseSkipsWithDependencyDiagnostics",
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
                @Provide(.shared)
                var a: ServiceA = ServiceA(name: "b")

                @Provide(.shared)
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

    @Test("mainActor option rejects a custom qualified actor named MainActor")
    func mainActorConflictWithCustomQualifiedMainActorProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @FeatureKit.MainActor
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

    @Test("mainActor option rejects a custom actor on a dependency member")
    func mainActorConflictOnDependencyMemberProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @FeatureKit.MainActor
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

    @Test("mainActor option rejects a custom actor on a sub-container member")
    func mainActorConflictOnSubContainerMemberProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @FeatureKit.MainActor
                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.mainactor-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("mainActor option rejects nonisolated dependency members")
    func mainActorConflictWithNonisolatedDependencyMemberProducesDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input)
                nonisolated var config: Config
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.mainactor-nonisolated-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("source-written property MainActor attributes are rejected as wrapper-ambiguous")
    func sourceWrittenPropertyMainActorAttributesAreRejected() {
        for actorName in ["MainActor", "Swift.MainActor", "_Concurrency.MainActor"] {
            assertMacroExpansionDiagnosticCodes(
                """
                @DIContainer(mainActor: true)
                struct AppContainer {
                    @\(actorName)
                    @Provide(.input)
                    var config: Config
                }
                """,
                expectedCodes: [
                    MessageID(
                        domain: "InnoDI.usage",
                        id: "provide.requires-direct-container-member"
                    )
                ],
                macros: Self.macros
            )
        }
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

    @Test("Custom init inside container body is rejected explicitly")
    func customInitInsideContainerBodyIsRejected() {
        let result = expandMacroSource(
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
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
            ]
        )
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
        #expect(!result.expansion.contains("_storage_config"))
        #expect(result.expansion.contains("self.config = config"))
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

    @Test("Conditional custom initializers in bodies and same-file extensions are rejected")
    func conditionalCustomInitializersAreRejected() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            #if DEBUG
            init(config: Config) {
                self.config = config
            }
            #endif
        }

        extension AppContainer {
            #if RELEASE
            init(config: Config, release: Bool) {
                self.init(config: config)
            }
            #endif
        }
        """

        let parsed = Parser.parse(source: source)
        let declaration = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let attribute = try #require(
            declaration.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let generated = try DIContainerMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(
            context.diagnostics.filter {
                $0.diagnosticID == MessageID(
                    domain: "InnoDI.validation",
                    id: "container.custom-init-unsupported"
                )
            }.count == 2
        )
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

    @Test("Class, actor, and enum containers emit the declaration-kind diagnostic")
    func unsupportedNominalKindsEmitDedicatedDiagnostic() throws {
        let classDecl = try #require(
            Parser.parse(source: "@DIContainer\nclass ClassContainer {}").statements.first?
                .item.as(ClassDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            classDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ClassContainer' is declared as a class. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let actorDecl = try #require(
            Parser.parse(source: "@DIContainer\nactor ActorContainer {}").statements.first?
                .item.as(ActorDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            actorDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ActorContainer' is declared as an actor. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let enumDecl = try #require(
            Parser.parse(source: "@DIContainer\nenum EnumContainer {}").statements.first?
                .item.as(EnumDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            enumDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'EnumContainer' is declared as an enum. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let protocolDecl = try #require(
            Parser.parse(source: "@DIContainer\nprotocol ProtocolContainer {}").statements.first?
                .item.as(ProtocolDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            protocolDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ProtocolContainer' is declared as a protocol. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let extensionDecl = try #require(
            Parser.parse(source: "@DIContainer\nextension ExtendedContainer {}").statements.first?
                .item.as(ExtensionDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            extensionDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ExtendedContainer' is declared as an extension. Convert it to a struct and inject runtime state through @Provide(.input)."
        )
    }

    @Test("Explicit private containers emit the access diagnostic")
    func privateContainerEmitsDedicatedDiagnostic() throws {
        let declaration = try #require(
            Parser.parse(
                source: "@DIContainer\nprivate struct PrivateContainer {}"
            ).statements.first?.item.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.private-access-unsupported",
            expectedMessage: "@DIContainer 'PrivateContainer' cannot be declared private in InnoDI 5.0 because generated child-mount APIs would not be accessible to sibling containers. Use fileprivate for file-local mounting, or place a default-access container inside a private enclosing namespace."
        )
        #expect(
            declaration.modifiers.first?.name.text == "private"
        )
    }

    @Test("Direct generic containers emit the generic diagnostic")
    func directGenericContainerEmitsDedicatedDiagnostic() throws {
        let declaration = try #require(
            Parser.parse(source: "@DIContainer\nstruct GenericContainer<Value> {}").statements.first?
                .item.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.generic-unsupported",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'GenericContainer' declares generic parameters. Move type-specific behavior behind an injected dependency."
        )
    }

    @Test("Containers nested in generic nominals emit the generic diagnostic")
    func genericOuterContainerEmitsDedicatedDiagnostic() throws {
        let outer = try #require(
            Parser.parse(
                source: "struct GenericOuter<Value> { @DIContainer struct NestedContainer {} }"
            ).statements.first?.item.as(StructDeclSyntax.self)
        )
        let declaration = try #require(
            outer.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.generic-unsupported",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'NestedContainer' is nested in generic context 'GenericOuter<Value>'. Move type-specific behavior behind an injected dependency."
        )

        let function = try #require(
            Parser.parse(
                source: "func make() { @DIContainer struct LocalContainer {} }"
            ).statements.first?.item.as(FunctionDeclSyntax.self)
        )
        let localDeclaration = try #require(
            function.body?.statements.first?.item.as(StructDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            localDeclaration,
            expectedID: "container.local-declaration-unsupported",
            expectedMessage: "@DIContainer supports only file-scope structs or structs nested in non-generic nominal declarations in InnoDI 5.0; 'LocalContainer' is declared in an executable code scope. Move the container to file scope or a non-generic nominal declaration."
        )
    }

    @Test("Containers nested in extensions fail closed")
    func extensionNestedContainerEmitsUnverifiableContextDiagnostic() throws {
        let source = Parser.parse(
            source: "struct ExtensionOuter {}\nextension ExtensionOuter { @DIContainer struct NestedContainer {} }"
        )
        let extensionDecl = try #require(
            source.statements.last?.item.as(ExtensionDeclSyntax.self)
        )
        let declaration = try #require(
            extensionDecl.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.unverifiable-enclosing-context",
            expectedMessage: "@DIContainer cannot prove that 'NestedContainer' has a non-generic context because it is declared inside extension 'ExtensionOuter'. Move the container to file scope or a non-generic nominal declaration."
        )
    }

    @Test("Unsupported stacked container macros emit one diagnostic without companion support")
    func unsupportedStackedContainerSuppressesCompanionExpansions() {
        assertMacroExpansionInline(
            """
            @DIComponent
            @DIHierarchyRoot
            @DIContainer
            final class UnsupportedContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared) var child: ChildContainer
            }
            """,
            expandedSource: """
                final class UnsupportedContainer {
                    var config: Config
                    var child: ChildContainer
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(
                        domain: "InnoDI.usage",
                        id: "container.unsupported-declaration-kind"
                    ),
                    message: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'UnsupportedContainer' is declared as a class. Convert it to a struct and inject runtime state through @Provide(.input).",
                    line: 3,
                    column: 1
                )
            ],
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
            })
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

    @Test("Factory parameter diagnostics suggest a typo fix-it when only a Damerau-Levenshtein match exists")
    func unresolvedFactoryParameterDiagnosticsIncludeTypoFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var apiClient: APIClient

            @Provide(.shared, factory: { (apiClent: APIClient) in
                Service(client: apiClent)
            })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse typo unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("apiClient") == true)
    }

    @Test("Factory parameter diagnostics omit a fix-it when no member is within typo distance")
    func unresolvedFactoryParameterDiagnosticsHaveNoFixItForFarMisses() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var apiClient: APIClient

            @Provide(.shared, factory: { (totallyDifferent: APIClient) in
                Service(client: totallyDifferent)
            })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse far-miss unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(diagnostic.fixIts.isEmpty)
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
            })
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
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
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
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
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
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
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

            @Provide(.shared, Service.self, with: [\\Self.base_url])
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
            @Provide(.shared, Service.self, with: [\\Self.later_service])
            var service: Service

            @Provide(.shared, factory: LaterService())
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
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
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

    // MARK: - @SubContainer

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

    @Test("@SubContainer(featureRoot:) generates the default SwiftUI root helper")
    func subContainerFeatureRootGeneratesDefaultHelper() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            public struct AppContainer {
                @Provide(.input) public var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.config], featureRoot: FeatureRootScene.self)
                public var feature: FeatureContainer
            }
            """,
            matches: "subContainerFeatureRootGeneratesDefaultHelper",
            macros: Self.macros
        )
    }

    @Test("mainActor: true propagates to generated SwiftUI root helpers")
    func mainActorSubContainerFeatureRootPropagatesIsolation() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            public struct AppContainer {
                @Provide(.input) public var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.config], featureRoot: FeatureRootScene.self)
                public var feature: FeatureContainer
            }
            """,
            matches: "mainActorSubContainerFeatureRootPropagatesIsolation",
            macros: Self.macros
        )
    }

    @Test("@SubContainer(featureRoots:) generates default and aliased SwiftUI root helpers")
    func subContainerFeatureRootsGenerateDefaultAndAliasHelpers() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            public struct AppContainer {
                @Provide(.input) public var config: AppConfig

                @SubContainer(
                    scope: .transient,
                    with: [\\.config],
                    featureRoots: [
                        FeatureRoot(FeatureRootScene.self),
                        FeatureRoot(FeatureShellScene.self, as: "featureShell")
                    ]
                )
                public var feature: FeatureContainer
            }
            """,
            matches: "subContainerFeatureRootsGenerateDefaultAndAliasHelpers",
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

    @Test("@SubContainer featureRoots rejects duplicate default roots")
    func subContainerFeatureRootsRejectDuplicateDefaults() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.config],
                    featureRoot: FeatureRootScene.self,
                    featureRoots: [
                        FeatureRoot(FeatureShellScene.self)
                    ]
                )
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-duplicate-default")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer featureRoots rejects invalid aliases")
    func subContainerFeatureRootsRejectInvalidAliases() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: [\\.config],
                    featureRoots: [
                        FeatureRoot(FeatureRootScene.self, as: "for")
                    ]
                )
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-invalid-alias")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer feature roots reject helper name conflicts")
    func subContainerFeatureRootRejectsHelperNameConflict() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                func featureRootView() -> ExistingRoot { fatalError() }

                @SubContainer(scope: .shared, with: [\\.config], featureRoot: FeatureRootScene.self)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "swiftui.feature-root-helper-name-conflict")
            ],
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

    @Test("`.shared` sub-container supports key-path same-label subset wiring")
    func subContainerSharedWithSubset() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [\\.config])
                var feature: FeatureContainer
            }
            """,
            matches: "subContainerSharedWithSubset",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports explicit empty with wiring")
    func subContainerSharedWithEmptySubset() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [])
                var feature: EmptyFeatureContainer
            }
            """,
            matches: "subContainerSharedWithEmptySubset",
            macros: Self.macros
        )
    }

    @Test("`.shared` sub-container supports explicit empty bindings wiring")
    func subContainerSharedWithEmptyBindings() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, bindings: [])
                var feature: EmptyFeatureContainer
            }
            """,
            matches: "subContainerSharedWithEmptyBindings",
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
                @Provide(.shared, factory: Logger()) var logger: Logger

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

    @Test("Invalid child wiring suppresses container support but keeps valid async peers")
    func invalidChildWiringKeepsValidAsyncPeerSupport() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var value: Int

                @Provide(asyncFactory: { () async -> Int in 1 })
                var asyncValue: Int

                @SubContainer(
                    scope: .transient,
                    with: [\\.value],
                    bindings: [(child: \\.value, parent: \\.value)]
                )
                var invalidChild: Child
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.map(\.diagnosticID) == [
            MessageID(
                domain: "InnoDI.validation",
                id: "sub.bindings-conflicts-with-with"
            )
        ])
        #expect(result.expansion.contains(
            "@InnoDI._InnoDIProvideAccessor(recovery: false)\n"
                + "    var asyncValue: Int"
        ))
        #expect(result.expansion.contains(
            "@InnoDI._InnoDISubContainerAccessor(recovery: true)\n"
                + "    var invalidChild: Child"
        ))
        #expect(!result.expansion.contains("_innoDISubBuild_invalidChild"))
        #expect(!result.expansion.contains("InnoDI.DeferredCell"))
    }

    @Test("@SubContainer with: requires a literal key-path array")
    func subContainerWithVariableDiagnosesInvalidSameNameWiring() {
        assertMacroExpansionDiagnosticCodes(
            """
            let keyPaths = [\\AppContainer.config]

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: keyPaths)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-same-name-wiring")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer with: rejects partially computed literal arrays")
    func subContainerWithComputedElementDiagnosesInvalidSameNameWiring() {
        assertMacroExpansionDiagnosticCodes(
            """
            func makeKeyPath() -> Any { fatalError() }

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [\\.config, makeKeyPath()])
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-same-name-wiring")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: requires a literal tuple key-path array")
    func subContainerBindingsVariableDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            let explicitBindings = [(child: \\FeatureBindingsContainer.featureConfig, parent: \\AppContainer.config)]

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, bindings: explicitBindings)
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: rejects malformed tuple entries")
    func subContainerBindingsMalformedTupleDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, bindings: [(child: \\.featureConfig)])
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: rejects duplicate labels inside a tuple")
    func subContainerBindingsDuplicateTupleLabelDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.input) var fallbackConfig: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureConfig, child: \\.fallbackConfig)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer bindings: rejects unknown labels inside a tuple")
    func subContainerBindingsUnknownTupleLabelDiagnosesInvalidBindings() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(source: \\.featureConfig, parent: \\.config)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings")
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

    @Test("@SubContainer with bindings: + non-literal with: prefers bindings-conflict diagnostic")
    func subContainerBindingsConflictPrecedesInvalidWiringDiagnoses() {
        // Locks the precedence ordering when both sub.bindings-conflicts-with-with
        // and sub.invalid-same-name-wiring would otherwise fire on the same
        // attribute. The validator suppresses the invalid-same-name-wiring
        // diagnostic when bindings-conflict is already emitted (see
        // DIContainerValidator's `hasBindingWiringConflict` guard).
        assertMacroExpansionDiagnosticCodes(
            """
            let keyPaths = [\\AppContainer.config]

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(
                    scope: .shared,
                    with: keyPaths,
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

    @Test("Generated implementation bindings use the canonical InnoDI namespace")
    func generatedImplementationBindingsUseCanonicalNamespace() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct FeatureContainer {}

            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(
                    .shared,
                    asyncFactory: { (config: AppConfig) async in Service(config: config) },
                )
                var service: Service

                @Provide(
                    .shared,
                    factory: { (request: Lazy<Request>) in Consumer(request: request) },
                )
                var consumer: Consumer

                @Provide(.transient, factory: Request())
                var request: Request

                @SubContainer(scope: .transient, with: [])
                var feature: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        for generatedName in [
            "_innoDIResolved_config",
            "_innoDITask_service",
            "_innoDILazyCell_request",
            "_innoDILazySelf",
            "_innoDISubBuildCell_feature",
            "_innoDILazySelfForSub",
            "_innoDIApplyOverrides",
            "_innoDIOverrides",
            "_innoDIOperation",
            "_innoDIContainer",
        ] {
            #expect(result.expansion.contains(generatedName))
        }
        for obsoleteName in [
            "let _resolved_config =",
            "let _task_service:",
            "_lazyCell_request",
            "_subBuildCell_feature",
            "let _lazySelf =",
            "let _lazySelfForSub =",
        ] {
            #expect(!result.expansion.contains(obsoleteName))
        }
    }

    @Test("validateDAG false emits typed fallback wrappers for unresolved deferred dependencies")
    func validateDAGFalseSupportsUnresolvedDeferredWrappers() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct ChildContainer {}

            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(
                    .shared,
                    factory: { (missingLazy: Lazy<Int>) in Service() },
                )
                var lazyService: Service

                @Provide(
                    .shared,
                    factory: { (missingProvider: Provider<Int>) in Service() },
                )
                var providerService: Service

                @Provide(
                    .shared,
                    asyncFactory: { (missingAsyncLazy: Lazy<Int>) async in Service() },
                )
                var asyncLazyService: Service

                @Provide(
                    .shared,
                    asyncFactory: { (missingAsyncProvider: Provider<Int>) async in Service() },
                )
                var asyncProviderService: Service

                @SubContainer(scope: .shared, with: [])
                var child: ChildContainer
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("internal.codegen-invariant"))
        for name in [
            "missingLazy",
            "missingProvider",
            "missingAsyncLazy",
            "missingAsyncProvider",
        ] {
            #expect(
                result.expansion.contains(
                    "InnoDI._innoDITrap(\"InnoDI could not resolve dependency '\(name)'"
                )
            )
        }
        #expect(result.expansion.contains("_storage_sub_child"))
    }

    @Test("unmanaged stored container state fails closed before initializer synthesis")
    func unmanagedStoredContainerMembersDiagnose() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                let token: Int
                var count = 0
                var observed = 0 { didSet {} }

                #if os(macOS)
                var conditional = "macOS"
                #endif

                static var shared = 0
                var computed: Int { 42 }

                @Provide(.input)
                var config: String
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == Array(
                repeating: MessageID(
                    domain: "InnoDI.usage",
                    id: "container.unmanaged-stored-property"
                ),
                count: 4
            )
        )
        #expect(!result.expansion.contains("init("))
        #expect(!result.expansion.contains("_storage_config"))
        #expect(!result.expansion.contains("struct Overrides"))
    }

    @Test("Former generated-local prefixes remain valid provider names")
    func formerGeneratedLocalPrefixesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var _resolved_config: Int
                @Provide(.input) var _task_service: Int
                @Provide(.input) var _lazyCell_request: Int
                @Provide(.input) var _subBuildCell_feature: Int
                @Provide(.input) var _lazySelf: Int
                @Provide(.input) var _lazySelfForSub: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
    }

    @Test("Container members starting with canonical reserved prefixes are rejected")
    func containerReservedNamePrefixDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var _storage_config: AppConfig
                @Provide(.input) var _override_config: AppConfig
                @Provide(.input) var _innoDIConfig: AppConfig
                @Provide(.input) var _InnoDIConfig: AppConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")
            ],
            macros: Self.macros
        )
    }

    @Test("Managed member named InnoDI cannot shadow generated runtime support")
    func containerReservedModuleNameDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var InnoDI: AppConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name")
            ],
            macros: Self.macros
        )
    }

    @Test("Direct nested types cannot shadow generated module qualifiers")
    func containerReservedNestedModuleNamesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                struct Swift {}
                enum _Concurrency {}
                typealias InnoDI = Int

                @Provide(.input) var config: AppConfig
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name")
            ],
            macros: Self.macros
        )
    }

    @Test("Container and enclosing nominal names cannot shadow generated module qualifiers")
    func containerReservedScopeModuleNamesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct Swift {
                @DIContainer
                struct FirstContainer {
                    @Provide(.input) var value: Int
                }
            }

            enum _Concurrency {
                @DIContainer
                struct SecondContainer {
                    @Provide(.input) var value: Int
                }
            }

            @DIContainer
            struct InnoDI {
                @Provide(.input) var value: Int
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-module-name"),
            ],
            macros: Self.macros
        )
    }

    @Test("Value members named Swift or _Concurrency remain available")
    func containerModuleValueNamesRemainAvailable() {
        let result = expandMacroSource(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input) var Swift: Int
                @Provide(.input) var _Concurrency: Int

                @Provide(
                    .shared,
                    asyncFactory: { () async in 1 },
                )
                var asyncValue: Int
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("@Swift.MainActor"))
        #expect(result.expansion.contains("_Concurrency.Task<Int, Swift.Never>"))
    }

    @Test("Plain direct declarations also honor reserved generated prefixes")
    func plainDirectDeclarationsHonorReservedPrefixes() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                struct _InnoDIHelper {}
                func _innoDIHelper() {}
                var _storage_probe: Int { 0 }
                typealias _override_Alias = Int
                #if DEBUG
                typealias _innoDIConditional = Int
                #endif
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix"),
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")
            ],
            macros: Self.macros
        )
    }

    @Test("@SubContainer member starting with reserved prefix emits container.reserved-name-prefix")
    func subContainerReservedNamePrefixDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.config])
                var _innoDISubBuild_feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.reserved-name-prefix")
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

    @Test("Escaped SubContainer property identifiers suppress every generated peer")
    func escapedSubContainerPropertyIdentifierFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var `default`: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.escaped-identifier-unsupported"
                )
            ]
        )
        for prefix in [
            "_storage_sub_",
            "_override_sub_",
            "_override_sub_apply_",
            "_innoDISubBuild_",
        ] {
            #expect(!result.expansion.contains(prefix))
        }
        #expect(!result.expansion.contains("_InnoDISubContainerAccessor"))
    }

    @Test("Standalone escaped SubContainer identifiers keep recovery unreachable")
    func standaloneEscapedSubContainerIdentifierDiagnoses() {
        let result = expandMacroSource(
            """
            struct StandaloneParent {
                @SubContainer(scope: .shared)
                var `default`: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.escaped-identifier-unsupported"
                )
            ]
        )
        #expect(!result.expansion.contains("_storage_sub_"))
        #expect(!result.expansion.contains("while true"))
    }

    @Test("Standalone SubContainer declarations are rejected")
    func standaloneSubContainerRequiresContainer() {
        assertMacroExpansionDiagnosticCodes(
            """
            struct StandaloneParent {
                @SubContainer(scope: .shared)
                var child: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.requires-direct-container-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Static SubContainer declarations are rejected")
    func staticSubContainerRequiresInstanceMember() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                static var child: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.requires-direct-container-member"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("SubContainer declaration matrix rejects non-plain storage")
    func subContainerDeclarationMatrixFailsClosed() {
        let declarations = [
            "let child: FeatureContainer",
            "lazy var child: FeatureContainer = .init()",
            "weak var child: FeatureContainer?",
            "unowned var child: FeatureContainer",
            "private(set) var child: FeatureContainer",
            "@MainActor var child: FeatureContainer",
            "@UnknownWrapper var child: FeatureContainer",
            "var child: FeatureContainer { .init() }",
            "var child: FeatureContainer { didSet {} }",
        ]

        for declaration in declarations {
            let result = expandMacroSource(
                """
                @DIContainer
                struct AppContainer {
                    @SubContainer(scope: .shared)
                    \(declaration)
                }
                """,
                macros: Self.macros
            )

            #expect(
                result.diagnostics.map(\.diagnosticID) == [
                    MessageID(
                        domain: "InnoDI.usage",
                        id: "sub.requires-direct-container-member"
                    )
                ]
            )
            #expect(!result.expansion.contains("_InnoDISubContainerAccessor"))
            #expect(!result.expansion.contains("_storage_sub_"))
            #expect(!result.expansion.contains("struct Overrides"))
            #expect(!result.expansion.contains("withOverrides"))
        }
    }

    @Test("Duplicate SubContainer attributes emit one public usage diagnostic")
    func duplicateSubContainerAttributesDiagnose() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                @SubContainer(scope: .shared)
                var child: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.usage", id: "sub.duplicate-attribute")
            ],
            macros: Self.macros
        )
    }

    @Test("Conditionally compiled SubContainer declarations fail closed")
    func conditionalSubContainerDeclarationDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                #if os(macOS)
                @SubContainer(scope: .shared)
                var child: FeatureContainer
                #endif
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.conditional-declaration-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Conditional SubContainer owns the terminal diagnostic before name validation")
    func conditionalEscapedSubContainerHasOneDiagnostic() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                #if os(macOS)
                @SubContainer(scope: .shared)
                var `default`: FeatureContainer
                #endif
            }
            """,
            expectedCodes: [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.conditional-declaration-unsupported"
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Hidden SubContainer support owns peers and accessors")
    func hiddenSubContainerSupportOwnsGeneration() throws {
        let parsed = Parser.parse(source: """
        @DIContainer
        struct AppContainer {
            @SubContainer(scope: .shared)
            @InnoDI._InnoDISubContainerAccessor(recovery: false)
            var child: FeatureContainer
        }
        """)
        guard let container = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let variable = container.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
              let support = findInnoDIAttribute(
                  named: "_InnoDISubContainerAccessor",
                  in: variable.attributes
              ) else {
            Issue.record("Should parse hidden SubContainer support")
            return
        }
        let context = TestMacroExpansionContext()
        let peers = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingPeersOf: variable,
            in: context
        )
        let accessors = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingAccessorsOf: variable,
            in: context
        )
        let peerText = peers.map(\.description).joined(separator: "\n")

        #expect(context.diagnostics.isEmpty)
        #expect(accessors.map(\.description).joined().contains("get"))
        #expect(peerText.contains("_storage_sub_child"))
        #expect(peerText.contains("_override_sub_apply_child"))
    }

    @Test("Hidden SubContainer support uses the nearest container isolation")
    func hiddenSubContainerSupportUsesNearestLexicalContainer() throws {
        let parsed = Parser.parse(source: """
        @DIContainer
        struct OuterContainer {
            @DIContainer(mainActor: true)
            struct InnerContainer {
                @SubContainer(scope: .transient)
                @InnoDI._InnoDISubContainerAccessor(recovery: false)
                var child: FeatureContainer
            }
        }
        """)
        let outer = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let inner = try #require(
            outer.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        let variable = try #require(
            inner.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let support = try #require(
            findInnoDIAttribute(
                named: "_InnoDISubContainerAccessor",
                in: variable.attributes
            )
        )
        let context = TestMacroExpansionContext(
            lexicalContext: [Syntax(inner), Syntax(outer)]
        )

        let peers = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingPeersOf: variable,
            in: context
        )
        let peerText = peers.map(\.description).joined(separator: "\n")

        #expect(context.diagnostics.isEmpty)
        #expect(peerText.contains("@Swift.MainActor"))
        #expect(peerText.contains("_innoDISubBuild_child"))
    }

    @Test("Hidden SubContainer recovery emits no peers")
    func hiddenSubContainerSupportRecoverySuppressesPeers() throws {
        let parsed = Parser.parse(source: """
        @DIContainer
        struct AppContainer {
            @SubContainer(scope: .shared)
            @InnoDI._InnoDISubContainerAccessor(recovery: true)
            var child: FeatureContainer
        }
        """)
        guard let container = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let variable = container.memberBlock.members.first?.decl.as(VariableDeclSyntax.self),
              let support = findInnoDIAttribute(
                  named: "_InnoDISubContainerAccessor",
                  in: variable.attributes
              ) else {
            Issue.record("Should parse hidden SubContainer recovery support")
            return
        }
        let context = TestMacroExpansionContext()
        let peers = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingPeersOf: variable,
            in: context
        )
        let accessors = try InnoDISubContainerAccessorMacro.expansion(
            of: support,
            providingAccessorsOf: variable,
            in: context
        )

        #expect(context.diagnostics.isEmpty)
        #expect(peers.isEmpty)
        #expect(accessors.map(\.description).joined().contains("while true"))
    }

    @Test("Source-attached hidden SubContainer support rejects the parent model")
    func manualSubContainerSupportAttachmentFailsClosed() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                @InnoDI._InnoDISubContainerAccessor(recovery: false)
                var child: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.usage",
                    id: "sub.generated-accessor-manual-attachment"
                )
            ]
        )
        #expect(!result.expansion.contains("struct Overrides"))
        #expect(!result.expansion.contains("withOverrides"))
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

    @Test("@Provide dynamic scope anchors provide.unknown-scope to the expression")
    func provideDynamicScopeAnchorsToExpression() {
        assertMacroExpansionSnapshot(
            """
            let requestedScope: DIScope = .shared

            @DIContainer
            struct AppContainer {
                @Provide(
                    requestedScope,
                    factory: Service(),
                )
                var service: Service
            }
            """,
            matches: "provideDynamicScopeAnchorsToExpression",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.usage", id: "provide.unknown-scope"),
                    message: "Unknown @Provide scope: requestedScope.",
                    line: 6,
                    column: 9
                )
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

                @Provide(.shared, factory: { (config: AppConfig) in
                    FeatureContainer(config: config)
                })
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
                @Provide(.transient, factory: Request()) var request: Request

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

    @Test("SubContainer validator failures select hidden recovery support")
    func subContainerValidatorFailureSelectsRecoverySupport() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.missing])
                var feature: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "sub.unknown-parent-member"
                )
            ]
        )
        #expect(
            result.expansion.contains(
                "_InnoDISubContainerAccessor(recovery: true)"
            )
        )
        #expect(
            !result.expansion.contains(
                "_InnoDISubContainerAccessor(recovery: false)"
            )
        )
        #expect(!result.expansion.contains("_storage_sub_feature"))
        #expect(!result.expansion.contains("struct Overrides"))
        #expect(!result.expansion.contains("withOverrides"))
    }

    @Test("Custom initializers preserve SubContainer source storage")
    func customInitializerPreservesSubContainerSourceStorage() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared, with: [])
                var feature: FeatureContainer

                init() {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.custom-init-unsupported"
                )
            ]
        )
        #expect(!result.expansion.contains("_InnoDISubContainerAccessor"))
        #expect(!result.expansion.contains("_storage_sub_feature"))
        #expect(!result.expansion.contains("struct Overrides"))
        #expect(!result.expansion.contains("withOverrides"))
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

    @Test("Implicit sub-container wiring requires explicit mapping when parent has multiple candidates")
    func subContainerAmbiguousAutoWiringDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.auto-wiring-ambiguous")
            ],
            macros: Self.macros
        )
    }

    @Test("Ambiguous sub-container auto-wiring offers a with: [...] template fix-it listing parent members")
    func subContainerAmbiguousAutoWiringOffersTemplateFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: AppConfig
            @Provide(.shared, factory: Logger()) var logger: Logger

            @SubContainer(scope: .shared)
            var feature: FeatureContainer
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse ambiguous auto-wiring fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "sub.auto-wiring-ambiguous")
        }) else {
            Issue.record("Expected sub.auto-wiring-ambiguous diagnostic")
            return
        }

        #expect(diagnostic.fixIts.count == 1)
        let fixItMessage = diagnostic.fixIts.first?.message.message ?? ""
        #expect(fixItMessage.contains("with:"))

        // The fix-it inserts `, with: [\.config, \.logger]` so both parent
        // member key paths are part of the synthesized change. We don't have
        // a direct way to assert the resulting source from a Diagnostic, but
        // verifying the change spans the expected text protects the contract
        // that the fix-it lists every parent member candidate.
        let combinedChanges = diagnostic.fixIts
            .flatMap(\.changes)
            .compactMap { change -> String? in
                if case let .replace(_, newNode) = change {
                    return newNode.description
                }
                if case let .replaceText(_, replacementText, _) = change {
                    return replacementText
                }
                return nil
            }
            .joined(separator: " ")
        #expect(combinedChanges.contains("\\.config"))
        #expect(combinedChanges.contains("\\.logger"))
    }

    @Test("Explicit empty with: wiring bypasses ambiguous implicit auto-wiring")
    func subContainerExplicitEmptyWithBypassesAmbiguousAutoWiring() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [])
                var feature: EmptyFeatureContainer
            }
            """,
            expectedCodes: [],
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

                @Provide(.transient, factory: { (config: AppConfig) in Request(config: config) })
                var request: Request

                @SubContainer(scope: .shared, with: [\\.request])
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

                @Provide(.transient, factory: { (config: AppConfig) in Request(config: config) })
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

    // `provide.lazy-aliased` / `provide.provider-aliased` warn
    // when a closure parameter uses a typealias that aliases `Lazy<T>` /
    // `Provider<T>`.
    @Test("Closure parameter using a Lazy typealias emits the lazy-aliased warning")
    func lazyAliasedParameterWarns() throws {
        let source = """
        struct Config {}
        typealias SomeLazy<T> = InnoDI.Lazy<T>

        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: Config())
            var config: Config

            @Provide(.shared, factory: { (config: SomeLazy<Config>) in Service(config: config) })
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
            @Provide(.shared, factory: { (foo: FooLazy) in Service(fooProvider: foo) })
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
            })
            var request: Request

            @Provide(.transient, factory: { (request: SomeProvider<Request>) in
                RequestLogger(provider: request)
            })
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
            @Provide(.shared, factory: { (config: AppConfig) in Service(config: config) })
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

private func assertUnsupportedContainerDeclaration(
    _ declaration: some DeclGroupSyntax,
    expectedID: String,
    expectedMessage: String
) throws {
    let attribute = try #require(
        declaration.attributes.first?.as(AttributeSyntax.self)
    )
    let context = TestMacroExpansionContext()

    let generated = try DIContainerMacro.expansion(
        of: attribute,
        providingMembersOf: declaration,
        in: context
    )

    #expect(generated.isEmpty)
    #expect(context.diagnostics.count == 1)
    #expect(
        context.diagnostics.first?.diagnosticID == MessageID(
            domain: "InnoDI.usage",
            id: expectedID
        )
    )
    #expect(context.diagnostics.first?.message == expectedMessage)
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
