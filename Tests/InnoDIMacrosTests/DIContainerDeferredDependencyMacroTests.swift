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

    @Test("Provider<T> detaches nested transient type factories from the container")
    func providerInSharedFactoryDetachesNestedTransientTypeFactories() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                @Provide(.transient, Request.self, with: [\\Self.config])
                var request: Request

                @Provide(.transient, Processor.self, with: [\\Self.request])
                var processor: Processor

                @Provide(.shared, factory: { (processor: Provider<Processor>) in
                    ProcessorLogger(processors: processor)
                })
                var logger: ProcessorLogger
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "processor ?? Processor(request: request ?? Request(config: config))"
            )
        )
        #expect(!result.expansion.contains("_lazySelf"))
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

}
