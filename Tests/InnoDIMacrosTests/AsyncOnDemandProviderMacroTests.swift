import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// `@Provide(.shared, initialization: .onDemand, asyncFactory:)` builds its
/// value on the first read through a compiler-owned cell, exposes a throwing
/// async accessor, and adds `closeAsyncProviders()` to its container.
@Suite("Async on-demand provider macro")
struct AsyncOnDemandProviderMacroTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Input": ProvideMacro.self,
        "Provide": ProvideMacro.self,
        "Multibinding": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
    ]

    private static func code(_ id: String) -> MessageID {
        MessageID(domain: "InnoDI.validation", id: id)
    }

    // MARK: - Expansion

    @Test("An async on-demand provider builds a cell and a close method")
    func asyncOnDemandProviderExpansion() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Input var client: APIClient

                @Provide(
                    .shared,
                    initialization: .onDemand,
                    asyncFactory: { (client: APIClient) async throws in
                        try await Session.open(client: client)
                    }
                )
                var session: Session

                @Provide(.shared, asyncFactory: { (session: Session) async throws in Profile(session: session) })
                var profile: Profile
            }
            """,
            matches: "asyncOnDemandProviderExpansion",
            macros: Self.macros
        )
    }

    @Test("A main-actor container isolates the operation and close method")
    func mainActorAsyncOnDemandProviderExpansion() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Input var store: Store

                @Provide(
                    .shared,
                    initialization: .onDemand,
                    asyncFactory: { (store: Store) async in await store.load() }
                )
                var snapshot: Snapshot
            }
            """,
            matches: "mainActorAsyncOnDemandProviderExpansion",
            macros: Self.macros
        )
    }

    @Test("A non-throwing async on-demand factory still reads through a throwing accessor")
    func asyncOnDemandAccessorAlwaysThrows() throws {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service
            }
            """
        let (peers, accessors) = try supportExpansion(source)
        #expect(peers == "private var _storage_service: InnoDI._InnoDIAsyncSharedCell<Service>? = nil")
        #expect(accessors == "getasyncthrows{return try await self._storage_service!.value()}")
    }

    @Test("Async on-demand consumers await the provider cell")
    func asyncOnDemandConsumersAwaitTheCell() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                @Provide(.shared, initialization: .onDemand, asyncFactory: { (service: Service) async throws in Client(service: service) })
                var client: Client

                @Provide(.transient, asyncFactory: { (client: Client) async throws in Request(client: client) })
                var request: Request
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("}(try await _innoDIOnDemandAsync_service.value())"))
        #expect(result.expansion.contains("await self._storage_service!.close()"))
        #expect(result.expansion.contains("await self._storage_client!.close()"))
        #expect(!result.expansion.contains("_innoDITask_service"))
        #expect(!result.expansion.contains("_innoDITraceOwner_service"))
        #expect(!result.expansion.contains("func prewarm"))
    }

    @Test("Containers without async on-demand providers do not gain a close method")
    func eagerAsyncProvidersHaveNoCloseMethod() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, asyncFactory: { () async in Service() })
                var service: Service
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("closeAsyncProviders"))
    }

    @Test("validateDAG: false keeps a forward async on-demand reference generatable")
    func forwardReferenceUsesFallbackWithoutDAGValidation() {
        let result = expandMacroSource(
            """
            @DIContainer(validateDAG: false)
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { (later: Service) async throws in Client(service: later) })
                var client: Client

                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var later: Service
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("}(later ?? InnoDI._innoDITrap("))
        #expect(result.expansion.contains("await self._storage_later!.close()"))
    }

    // MARK: - Effects

    @Test("A synchronous consumer cannot read an async on-demand provider")
    func synchronousConsumerIsRejected() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                @Provide(.transient, factory: { (service: Service) in Client(service: service) })
                var client: Client
            }
            """,
            expectedCodes: [Self.code("provide.async-dependency-requires-async-consumer")],
            macros: Self.macros
        )
    }

    @Test("A non-throwing async consumer cannot read an async on-demand provider")
    func nonThrowingAsyncConsumerIsRejected() {
        for consumer in [
            "@Provide(.shared, asyncFactory: { (service: Service) async in Client(service: service) })",
            "@Provide(.transient, asyncFactory: { (service: Service) async in Client(service: service) })",
            "@Provide(.shared, initialization: .onDemand, asyncFactory: { (service: Service) async in Client(service: service) })",
        ] {
            assertMacroExpansionDiagnosticCodes(
                """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                    var service: Service

                    \(consumer)
                    var client: Client
                }
                """,
                expectedCodes: [Self.code("provide.throwing-dependency-requires-throwing-consumer")],
                macros: Self.macros
            )
        }
    }

    @Test("with:, Lazy, and multibinding edges reject async on-demand targets")
    func synchronousEdgeKindsRejectAsyncOnDemandTargets() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                @Provide(.transient, Client.self, with: [\\Self.service])
                var client: Client
            }
            """,
            expectedCodes: [Self.code("provide.with-dependency-requires-synchronous-provider")],
            macros: Self.macros
        )
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                @Provide(.shared, factory: { (service: Lazy<Service>) in Client(service: service) })
                var client: Client
            }
            """,
            expectedCodes: [Self.code("provide.lazy-unsupported-target")],
            macros: Self.macros
        )
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                @Multibinding([\\Self.service])
                var services: [Service]
            }
            """,
            expectedCodes: [Self.code("multibinding.async-contributor")],
            macros: Self.macros
        )
    }

    // MARK: - Generated names

    @Test("The generated close method name is reserved")
    func closeMethodNameConflict() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                func closeAsyncProviders() {}
            }
            """,
            expectedCodes: [Self.code("container.close-async-providers-name-conflict")],
            macros: Self.macros
        )
    }

    @Test("Without an async on-demand provider the close method name stays available")
    func closeMethodNameIsFreeWithoutAsyncOnDemandProviders() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, factory: Service())
                var service: Service

                func closeAsyncProviders() {}
            }
            """,
            macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
    }

    @Test("An async on-demand provider claims _storage_, not eager task storage")
    func asyncOnDemandProviderClaimsValueStorage() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in Service() })
                var service: Service

                @Provide(.shared, factory: Service())
                var task_service: Service
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    /// Runs the compiler-owned support macro's peer and accessor roles on the
    /// first member of the first container in `source`.
    private func supportExpansion(_ source: String) throws -> (peers: String, accessors: String) {
        let parsed = Parser.parse(source: source)
        let container = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let variable = try #require(
            container.memberBlock.members.first?.decl.as(VariableDeclSyntax.self)
        )
        let generatedAttributeSource = Parser.parse(
            source: "@InnoDI._InnoDIProvideAccessor(recovery: false) var value: Int"
        )
        let generatedVariable = try #require(
            generatedAttributeSource.statements.first?.item.as(VariableDeclSyntax.self)
        )
        let generatedAttribute = try #require(
            generatedVariable.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()
        let peers = try InnoDIProvideAccessorMacro.expansion(
            of: generatedAttribute,
            providingPeersOf: variable,
            in: context
        )
        let accessors = try InnoDIProvideAccessorMacro.expansion(
            of: generatedAttribute,
            providingAccessorsOf: variable,
            in: context
        )
        #expect(context.diagnostics.isEmpty)
        return (
            peers.map(\.description).joined(separator: "\n"),
            accessors.map(\.description).joined(separator: "\n")
        )
    }
}
