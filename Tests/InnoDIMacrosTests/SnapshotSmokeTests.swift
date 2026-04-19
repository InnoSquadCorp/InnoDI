import InnoDITestSupport
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Macro snapshot helper smoke")
struct SnapshotSmokeTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
    ]

    @Test("Input-only container expands to expected init shape")
    func inputOnlyContainerSnapshot() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var baseURL: String
            }
            """

        assertMacroExpansionSnapshot(
            source,
            matches: "inputOnlyContainer",
            macros: Self.macros
        )
    }

    @Test("Missing concrete opt-in reports a diagnostic with a Fix-It")
    func concreteOptInDiagnosticInline() {
        let source = """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """

        assertMacroExpansionInline(
            source,
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
}
