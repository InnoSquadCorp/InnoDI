import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Parent-side sub-container key paths name exactly one direct member as
/// `\Self.member`. InnoDI reads only the member name, so a named root is
/// rejected with a fix-it and nested components are rejected as invalid.
@Suite("Parent key path spelling")
struct ParentKeyPathSpellingTests {
    private static let macros: [String: any Macro.Type] = [
        "DIContainer": DIContainerMacro.self,
        "Input": ProvideMacro.self,
        "Provide": ProvideMacro.self,
        "_InnoDIProvideAccessor": InnoDIProvideAccessorMacro.self,
        "SubContainer": SubContainerMacro.self,
        "_InnoDISubContainerAccessor": InnoDISubContainerAccessorMacro.self,
        "SubContainerFactory": ProvideMacro.self,
    ]

    private static let noncanonical = MessageID(
        domain: "InnoDI.validation",
        id: "sub.noncanonical-parent-key-path"
    )

    @Test("A named root in with: is rejected and the fix-it spells \\Self")
    func namedRootInWithIsRepaired() throws {
        let source = """
            @DIContainer
            struct AppContainer {
                @Input var config: AppConfig

                @SubContainer(scope: .shared, with: [\\AppContainer.config])
                var feature: FeatureContainer
            }
            """
        let result = expandMacroSource(source, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [Self.noncanonical])

        let repair = try repairNoncanonicalKeyPath(in: source)
        #expect(
            repair.message
                == "'feature' reads parent member 'config' through \\AppContainer.config. InnoDI reads only the member name, so a named root is never checked against the declaring container. Spell parent key paths as \\Self.config."
        )
        #expect(repair.fixItMessage == "Replace with '\\Self.config'")
        let repaired = repair.repaired
        #expect(repaired.contains("with: [\\Self.config]"))
        #expect(!repaired.contains("\\AppContainer.config"))
        #expect(expandMacroSource(repaired, macros: Self.macros).diagnostics.isEmpty)
    }

    @Test("A named parent root in bindings: is rejected while the child root stays")
    func namedParentRootInBindingsIsRepaired() throws {
        let source = """
            @DIContainer
            struct AppContainer {
                @Input var settings: AppConfig

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\FeatureContainer.config, parent: \\AppContainer.settings)]
                )
                var feature: FeatureContainer
            }
            """
        let result = expandMacroSource(source, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [Self.noncanonical])
        let repaired = try repairNoncanonicalKeyPath(in: source).repaired
        #expect(
            repaired.contains(
                "(child: \\FeatureContainer.config, parent: \\Self.settings)"
            )
        )
        #expect(expandMacroSource(repaired, macros: Self.macros).diagnostics.isEmpty)
    }

    @Test("A named parent root in @SubContainerFactory bindings: is rejected")
    func namedParentRootInFactoryBindingsIsRejected() throws {
        let source = """
            @DIContainer
            struct AppContainer {
                @Input var repository: Repository

                @SubContainerFactory(
                    SessionContainer.self,
                    bindings: [(child: \\SessionContainer.repository, parent: \\AppContainer.repository)]
                )
                var session: SessionContainer.AssistedFactory
            }
            """
        let result = expandMacroSource(source, macros: Self.macros)
        #expect(result.diagnostics.contains { $0.diagnosticID == Self.noncanonical })
        let repair = try repairNoncanonicalKeyPath(in: source)
        #expect(repair.fixItMessage == "Replace with '\\Self.repository'")
        #expect(
            repair.repaired.contains(
                "(child: \\SessionContainer.repository, parent: \\Self.repository)"
            )
        )
    }

    @Test("Self-rooted and rootless parent key paths stay canonical")
    func canonicalSpellingsPass() {
        for wiring in ["with: [\\Self.config]", "with: [\\.config]"] {
            let result = expandMacroSource(
                """
                @DIContainer
                struct AppContainer {
                    @Input var config: AppConfig

                    @SubContainer(scope: .shared, \(wiring))
                    var feature: FeatureContainer
                }
                """,
                macros: Self.macros
            )
            #expect(result.diagnostics.isEmpty, Comment(rawValue: wiring))
        }
    }

    @Test("Nested parent components are invalid instead of reading the last component")
    func nestedComponentsAreInvalid() {
        let nestedWith = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Input var config: AppConfig

                @SubContainer(scope: .shared, with: [\\Self.config.baseURL])
                var feature: FeatureContainer
            }
            """,
            macros: Self.macros
        )
        #expect(
            nestedWith.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.validation", id: "sub.invalid-same-name-wiring"),
            ]
        )

        for binding in [
            "(child: \\FeatureContainer.config, parent: \\Self.settings.config)",
        ] {
            let nestedBindings = expandMacroSource(
                """
                @DIContainer
                struct AppContainer {
                    @Input var settings: AppConfig

                    @SubContainer(scope: .shared, bindings: [\(binding)])
                    var feature: FeatureContainer
                }
                """,
                macros: Self.macros
            )
            #expect(
                nestedBindings.diagnostics.map(\.diagnosticID) == [
                    MessageID(domain: "InnoDI.validation", id: "sub.invalid-bindings"),
                ],
                Comment(rawValue: binding)
            )
        }
    }

    /// Runs the container member macro on the parsed declaration so fix-it
    /// ranges are positions in `source`, then applies the first fix-it of the
    /// noncanonical parent key path diagnostic.
    private func repairNoncanonicalKeyPath(in source: String) throws -> (
        message: String,
        fixItMessage: String,
        repaired: String
    ) {
        let parsed = Parser.parse(source: source)
        let declaration = try #require(
            parsed.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        )
        let attribute = try #require(declaration.attributes.first?.as(AttributeSyntax.self))
        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            in: context
        )
        let diagnostic = try #require(
            context.diagnostics.first { $0.diagnosticID == Self.noncanonical }
        )
        let fixIt = try #require(diagnostic.fixIts.first)
        var bytes = Array(source.utf8)
        for change in fixIt.changes {
            guard case let .replaceText(range, replacement, _) = change else { continue }
            bytes.replaceSubrange(
                range.lowerBound.utf8Offset..<range.upperBound.utf8Offset,
                with: Array(replacement.utf8)
            )
        }
        return (
            diagnostic.message,
            fixIt.message.message,
            String(decoding: bytes, as: UTF8.self)
        )
    }
}
