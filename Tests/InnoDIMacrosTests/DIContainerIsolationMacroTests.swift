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

}
