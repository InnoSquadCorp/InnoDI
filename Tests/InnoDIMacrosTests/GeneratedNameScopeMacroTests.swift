import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Accepted declarations whose expansion used to reference a name the
/// generated code itself shadowed or left out of scope. The real-compiler
/// counterparts live in `GeneratedNameScopeRuntimeTests` and
/// `CustomGlobalActorContainerRuntimeTests`.
@Suite("Generated name scoping")
struct GeneratedNameScopeMacroTests {
    private static let macros: [String: any Macro.Type] =
        DIContainerMacroTests.macros.merging([
            "DIContainerRole": DIContainerRoleMacro.self,
            "AssistedFactory": AssistedFactoryMacro.self,
        ]) { _, new in new }

    private static func code(_ id: String) -> MessageID {
        MessageID(domain: "InnoDI.validation", id: id)
    }

    // MARK: - Custom global actor (M1)

    @Test("A custom global actor container keeps its async withOverrides isolated")
    func customGlobalActorContainerInheritsIsolation() {
        assertMacroExpansionSnapshot(
            """
            @FeatureActor
            @DIContainer
            struct FeatureContainer {
                @Input var seed: Int
            }
            """,
            matches: "customGlobalActorContainerInheritsIsolation",
            macros: Self.macros
        )
    }

    @Test("A nested assisted factory receives the container's custom actor")
    func customGlobalActorAssistedFactoryInheritsActor() {
        let source = { (factoryAttribute: String) in
            """
            @FeatureActor
            @DIContainer
            struct Session {
                @Input var seed: Int
                @Input(.assisted) var request: Int
                @AssistedFactory(Session.self, static: [\\Session.seed], assisted: [\\Session.request])
                \(factoryAttribute)struct AssistedFactory {}
            }
            """
        }
        let inherited = expandMacroSource(source(""), macros: Self.macros)
        #expect(inherited.diagnostics.isEmpty)
        #expect(inherited.expansion.components(separatedBy: "@FeatureActor").count - 1 == 2)

        // A factory that already names an actor keeps exactly its own.
        for explicit in ["@FeatureActor ", "@OtherActor ", "@MainActor "] {
            let result = expandMacroSource(source(explicit), macros: Self.macros)
            #expect(result.diagnostics.isEmpty)
            #expect(result.expansion.components(separatedBy: "@FeatureActor").count - 1
                == (explicit == "@FeatureActor " ? 2 : 1))
        }
    }

    @Test("A component role rejects a custom global actor")
    func componentRejectsCustomGlobalActor() {
        assertMacroExpansionDiagnosticCodes(
            """
            @FeatureActor
            @DIContainerRole(role: ContainerRole.component)
            struct FeatureContainer {
                @Input var seed: Int
            }
            """,
            expectedCodes: [Self.code("component.custom-global-actor-unsupported")],
            macros: Self.macros
        )

        // Main-actor components keep their dedicated mounting protocol.
        for prefix in ["@MainActor\n", ""] {
            let suffix = prefix.isEmpty ? ", mainActor: true" : ""
            let result = expandMacroSource(
                """
                \(prefix)@DIContainerRole(role: ContainerRole.component\(suffix))
                struct FeatureContainer {
                    @Input var seed: Int
                }
                """,
                macros: Self.macros
            )
            #expect(result.diagnostics.isEmpty)
            #expect(result.expansion.contains("_InnoDIMainActorComponentMountable"))
        }
    }

    @Test("mainActor: true with a custom actor still reports only the existing conflict")
    func componentMainActorConflictIsNotDuplicated() {
        assertMacroExpansionDiagnosticCodes(
            """
            @FeatureActor
            @DIContainerRole(role: ContainerRole.component, mainActor: true)
            struct FeatureContainer {
                @Input var seed: Int
            }
            """,
            expectedCodes: [Self.code("container.mainactor-conflict")],
            macros: Self.macros
        )
    }

    // MARK: - withOverrides generic parameter (M2)

    @Test("withOverrides uses a reserved generic parameter beside an input named OperationResult")
    func operationResultInputUsesReservedGenericName() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct HistoryContainer {
                @Input var last: OperationResult
            }
            """,
            matches: "operationResultInputUsesReservedGenericName",
            macros: Self.macros
        )
        let result = expandMacroSource(
            """
            @DIContainer
            struct HistoryContainer {
                @Input var last: OperationResult
            }
            """,
            macros: Self.macros
        )
        #expect(result.expansion.components(separatedBy: "withOverrides<_InnoDIOperationResult>").count - 1 == 4)
        #expect(!result.expansion.contains("<OperationResult>"))
        #expect(!result.expansion.contains("-> OperationResult"))
    }

    // MARK: - Transient sub-container override binding (M3)

    @Test("A transient child's override binding cannot capture a parent input named apply")
    func transientChildFromInputNamedApply() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct Parent {
                @Input var apply: Int
                @SubContainer(scope: .transient, with: [\\Self.apply])
                var child: Child
            }
            """,
            matches: "transientChildFromInputNamedApply",
            macros: Self.macros
        )
    }

    // MARK: - missingEffectOverrides requirement (M4)

    @Test("An override slot named missingEffectOverrides is rejected beside an effect provider", arguments: [
        """
        @Provide(.shared, effect: .sideEffect, factory: 1) var missingEffectOverrides: Int
        """,
        """
        @Provide(.shared, effect: .sideEffect, factory: 1) var marker: Int
        @Provide(.transient, factory: 2) var missingEffectOverrides: Int
        """,
        """
        @Provide(.shared, effect: .sideEffect, factory: 1) var marker: Int
        @SubContainer(scope: .shared, with: []) var missingEffect: Child
        """,
        """
        @Provide(.shared, effect: .sideEffect, factory: 1) var marker: Int
        @SubContainer(scope: .shared, with: []) var missingEffectOverrides: Child
        """,
    ])
    func missingEffectOverridesSlotIsRejected(members: String) {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct EffectContainer {
                \(members)
            }
            """,
            expectedCodes: [Self.code("container.missing-effect-overrides-name-conflict")],
            macros: Self.macros
        )
    }

    @Test("Neighbors of the effect-validation requirements still expand", arguments: [
        """
        @Provide(.shared, effect: .sideEffect, factory: 1) var requiredEffectOverrides: Int
        @Provide(.shared, effect: .sideEffect, factory: 2) var missing: Int
        @Provide(.shared, effect: .sideEffect, factory: 3) var set: Int
        @Provide(.shared, effect: .sideEffect, factory: 4) var useDefault: Int
        """,
        // Without an effect-marked provider no requirement is synthesized.
        """
        @Provide(.shared, factory: 1) var missingEffectOverrides: Int
        """,
        // Inputs have no override slot.
        """
        @Input var missingEffectOverrides: Int
        @Provide(.shared, effect: .sideEffect, factory: 1) var marker: Int
        """,
    ])
    func missingEffectOverridesNeighborsExpand(members: String) {
        let result = expandMacroSource(
            """
            @DIContainer
            struct EffectContainer {
                \(members)
            }
            """,
            macros: Self.macros
        )
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("struct Overrides"))
    }

    // MARK: - Component dependency protocol (M5)

    @Test("A component's peer dependency protocol qualifies the container's nested types")
    func componentDependenciesQualifyNestedTypes() {
        assertMacroExpansionSnapshot(
            """
            @DIContainerRole(role: ContainerRole.component)
            struct FeatureComponent {
                enum Mode { case a, b }
                struct Settings {}
                typealias Handler = (Mode) -> Void

                @Input var mode: Mode
                @Input var optionalMode: Mode?
                @Input var modes: [Mode]
                @Input var settings: [Mode: Settings]
                @Input var onChange: (Mode) -> Void
                @Input(escaping: true) var handler: Handler
                @Input var selfMode: Self.Mode
                @Input var external: Swift.Optional<Outer.Mode>
                @Input var label: String
            }
            """,
            matches: "componentDependenciesQualifyNestedTypes",
            macros: Self.macros
        )
    }
}
