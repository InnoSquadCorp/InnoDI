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

    @Test("contributors must match the collection element type")
    func rejectsMismatchedContributor() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct InvalidContainer {
                @Provide(.shared, factory: 42)
                var count: Int

                @Multibinding([\\Self.count])
                var values: [String]
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID).contains(
                MessageID(
                    domain: "InnoDI.validation",
                    id: "multibinding.type-mismatch"
                )
            )
        )
    }
}
