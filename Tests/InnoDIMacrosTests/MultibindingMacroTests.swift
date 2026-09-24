import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Multibinding")
struct MultibindingMacroTests {
    private static let macros: [String: any Macro.Type] =
        DIContainerMacroTests.macros.merging([
            "Multibinding": ProvideMacro.self,
        ]) { _, new in new }

    @Test("ordered collection is injectable and overrideable")
    func expandsOrderedCollection() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct NetworkContainer {
                @Provide(.shared, factory: AuthInterceptor())
                var auth: any RequestInterceptor

                @Provide(.transient, factory: LoggingInterceptor())
                var logging: any RequestInterceptor

                @Multibinding([\\Self.auth, \\Self.logging])
                var interceptors: [any RequestInterceptor]

                @Provide(.transient, factory: { interceptors in
                    Client(interceptors: interceptors)
                })
                var client: Client
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(
            result.expansion.contains(
                "@InnoDI._InnoDIProvideAccessor(recovery: false)\n    var interceptors"
            )
        )
        #expect(
            result.expansion.contains(
                "interceptors: [any RequestInterceptor]? = nil"
            )
        )
        #expect(result.expansion.contains("self._override_interceptors = interceptors"))
    }

    @Test("concrete contributors defer existential conversion to the compiler")
    func acceptsConcreteContributorForExistentialCollection() {
        let result = expandMacroSource(
            """
            protocol Service {}
            struct LiveService: Service {}

            @DIContainer
            struct ValidContainer {
                @Provide(.shared, factory: LiveService())
                var live: LiveService

                @Multibinding([\\Self.live])
                var services: [any Service]
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("@InnoDI._InnoDIProvideAccessor(recovery: false)"))
    }

    @Test("an explicit empty contribution is valid")
    func acceptsExplicitEmptyCollection() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct EmptyContainer {
                @Multibinding([])
                var values: [String]
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("var values: [String]"))
    }

    @Test("explicit collection metadata rejects duplicate keys and unknown contributors")
    func rejectsInvalidExplicitCollectionMetadata() {
        let semanticResult = expandMacroSource(
            """
            @DIContainer
            struct InvalidContainer {
                @Provide(.shared, asyncFactory: { await load() })
                var remote: Service

                @Provide(
                    .transient,
                    collection: .keyedProviders([
                        .init(key: "remote", contributor: \\Self.remote),
                        .init(key: "missing", contributor: \\Self.missing),
                    ]),
                    factory: makeProviders()
                )
                var providers: DIKeyedProviderCollection<String, Service>

            }
            """,
            macros: Self.macros
        )
        let duplicateResult = expandMacroSource(
            """
            @DIContainer
            struct DuplicateContainer {
                @Provide(.shared, factory: Service()) var remote: Service
                @Provide(
                    .transient,
                    collection: .keyedProviders([
                        .init(key: "same", contributor: \\Self.remote),
                        .init(key: "same", contributor: \\Self.remote),
                    ]),
                    factory: makeProviders()
                )
                var providers: DIKeyedProviderCollection<String, Service>
            }
            """,
            macros: Self.macros
        )

        let ids = Set(
            (semanticResult.diagnostics + duplicateResult.diagnostics)
                .map(\.diagnosticID)
        )
        #expect(ids.contains(MessageID(
            domain: "InnoDI.validation",
            id: "provide.duplicate-collection-key"
        )))
        #expect(ids.contains(MessageID(
            domain: "InnoDI.validation",
            id: "provide.async-collection-contributor"
        )))
        #expect(ids.contains(MessageID(
            domain: "InnoDI.validation",
            id: "provide.unknown-collection-contributor"
        )))
    }

    @Test("collection metadata accepts explicit empty provider groups")
    func acceptsExplicitEmptyProviderMetadata() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct EmptyContainer {
                @Provide(
                    .transient,
                    collection: .keyedProviders([]),
                    factory: { DIKeyedProviderCollection<String, Int>.empty }
                )
                var providers: DIKeyedProviderCollection<String, Int>
            }
            """,
            macros: Self.macros
        )

        #expect(result.diagnostics.isEmpty)
    }
}
