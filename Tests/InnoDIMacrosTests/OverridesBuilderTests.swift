import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Snapshot matrix for the `@DIContainer` Overrides builder feature.
///
/// These tests pin the generated `struct Overrides`, convenience `init(_ applyOverrides:)`,
/// and four `static withOverrides` effect overloads across the dimensions that
/// drive the code path: input/shared/transient mix, async shared, MainActor
/// propagation, public access, input-only scaffolding, and user-defined
/// `Overrides` name conflict.
@Suite("@DIContainer Overrides builder")
struct OverridesBuilderTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "InnoDI._InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
    ]

    @Test("input + shared + transient mix generates full Overrides scaffolding")
    func inputSharedTransientAll() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var userID: String

                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient

                @Provide(.transient, factory: { ViewModel() })
                var viewModel: ViewModel
            }
            """,
            matches: "inputSharedTransientAll",
            macros: Self.macros
        )
    }

    @Test("shared-only container: convenience init drops input params, keeps overrides")
    func sharedOnly() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            matches: "sharedOnly",
            macros: Self.macros
        )
    }

    @Test("transient-only container: Overrides uses T? (not closure)")
    func transientOnly() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.transient, factory: { ViewModel() })
                var viewModel: ViewModel
            }
            """,
            matches: "transientOnly",
            macros: Self.macros
        )
    }

    @Test("async shared override remains T? (not Task-wrapped)")
    func asyncSharedOverride() {
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
            matches: "asyncSharedOverride",
            macros: Self.macros
        )
    }

    @Test("mainActor: true isolates Overrides, convenience init, and withOverrides")
    func mainActorPropagation() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer(mainActor: true)
            struct AppContainer {
                @Provide(.input)
                var userID: String

                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            matches: "mainActorPropagation",
            macros: Self.macros
        )
    }

    @Test("public container propagates public to Overrides + convenience init + withOverrides")
    func publicContainer() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            public struct AppContainer {
                @Provide(.input)
                var userID: String

                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            matches: "publicContainer",
            macros: Self.macros
        )
    }

    @Test("input-only container now generates empty Overrides scaffolding")
    func inputOnlySkipsScaffolding() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var userID: String

                @Provide(.input)
                var baseURL: String
            }
            """,
            matches: "inputOnlySkipsScaffolding",
            macros: Self.macros
        )
    }

    @Test("empty container generates the complete mountable Overrides ABI")
    func emptyContainerGeneratesScaffolding() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct EmptyContainer {}
            """,
            matches: "emptyContainerGeneratesScaffolding",
            macros: Self.macros
        )
    }

    @Test("input-only container with user-defined Overrides fails closed")
    func inputOnlyUserDefinedOverridesSkipsConflictWarning() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                struct Overrides {
                    var custom: String
                }

                @Provide(.input)
                var userID: String
            }
            """,
            matches: "inputOnlyUserDefinedOverridesSkipsConflictWarning",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "container.overrides-name-conflict"),
                    message: "A nested 'Overrides' struct is already declared, so @DIContainer cannot synthesize its required override API. Rename the user declaration; custom Overrides types are unsupported in InnoDI 6.0.",
                    line: 3,
                    column: 5,
                    severity: .error
                )
            ],
            macros: Self.macros
        )
    }

    @Test("user-defined nested 'Overrides' emits a recovery initializer with an error")
    func userDefinedOverridesConflict() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                struct Overrides {
                    var custom: String
                }

                @Provide(.input)
                var userID: String

                @Provide(.shared, factory: APIClient())
                var apiClient: APIClient
            }
            """,
            matches: "userDefinedOverridesConflict",
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(domain: "InnoDI.validation", id: "container.overrides-name-conflict"),
                    message: "A nested 'Overrides' struct is already declared, so @DIContainer cannot synthesize its required override API. Rename the user declaration; custom Overrides types are unsupported in InnoDI 6.0.",
                    line: 3,
                    column: 5,
                    severity: .error
                )
            ],
            macros: Self.macros
        )
    }

    @Test("Overrides conflict lookup covers protocols, #if branches, and escaped names")
    func overridesConflictLookupCoversAllDirectTypeDeclarations() throws {
        let source = Parser.parse(
            source: """
            struct ProtocolContainer {
                protocol Overrides {}
            }

            struct ConditionalContainer {
                #if os(macOS)
                struct Overrides {}
                #endif
            }

            struct EscapedContainer {
                struct `Overrides` {}
            }

            struct NestedNonConflictContainer {
                struct Namespace {
                    struct Overrides {}
                }
            }
            """
        )
        let declarations = source.statements.compactMap {
            $0.item.as(StructDeclSyntax.self)
        }

        #expect(declarations.count == 4)
        let protocolConflict = DIContainerParser.findOverridesNameConflict(
            in: try #require(declarations.first)
        )
        let conditionalConflict = DIContainerParser.findOverridesNameConflict(
            in: try #require(declarations.dropFirst().first)
        )
        let escapedConflict = DIContainerParser.findOverridesNameConflict(
            in: try #require(declarations.dropFirst(2).first)
        )
        let nestedNonConflict = DIContainerParser.findOverridesNameConflict(
            in: try #require(declarations.dropFirst(3).first)
        )

        #expect(protocolConflict?.kind == "protocol")
        #expect(conditionalConflict?.kind == "struct")
        #expect(escapedConflict?.kind == "struct")
        #expect(nestedNonConflict == nil)
    }
}
