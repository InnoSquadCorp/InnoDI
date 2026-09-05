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
}
