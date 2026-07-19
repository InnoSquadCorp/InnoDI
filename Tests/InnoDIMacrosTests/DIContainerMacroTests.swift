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
    /// Shared across the base suite and its SubContainer-focused extension.
    static let macros: [String: any Macro.Type] = [
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
