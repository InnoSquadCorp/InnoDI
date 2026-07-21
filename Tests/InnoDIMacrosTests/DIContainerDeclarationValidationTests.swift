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
    @Test("Custom init inside container body is rejected explicitly")
    func customInitInsideContainerBodyIsRejected() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config

                init(config: Config) {
                    self.config = config
                }
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
            ]
        )
        #expect(!result.expansion.contains("_InnoDIProvideAccessor"))
        #expect(!result.expansion.contains("_storage_config"))
        #expect(result.expansion.contains("self.config = config"))
    }

    // NOTE: Tests involving same-file `extension AppContainer { init ... }` detection
    // continue to use the direct `DIContainerMacro.expansion(of:providingMembersOf:in:)`
    // call pattern. The `SwiftSyntaxMacroExpansion.expand()` pipeline detaches the
    // declaration from its parent chain, so the macro's `sourceFile(containing:)` walk
    // returns `nil` and sibling extensions are not discovered.
    @Test("Custom init inside same-file extension is rejected explicitly")
    func customInitInsideSameFileExtensionIsRejected() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }

        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse container with same-file extension init")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        })
    }

    @Test("Other same-file extensions do not trigger custom init rejection")
    func customInitInOtherSameFileExtensionDoesNotTriggerRejection() {
        assertMacroExpansionSnapshot(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config
            }

            struct Helper {
                let value: Int
            }

            extension Helper {
                init(value: Int, doubled: Bool) {
                    self.init(value: value * (doubled ? 2 : 1))
                }
            }
            """,
            matches: "customInitInOtherSameFileExtensionDoesNotTriggerRejection",
            macros: Self.macros
        )
    }

    @Test("All offending initializers in body and same-file extension are diagnosed")
    func allOffendingInitializersAreDiagnosed() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            init(config: Config) {
                self.config = config
            }
        }

        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }

            init(config: Config, retries: Int) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse container with multiple offending inits")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let diagnostics = context.diagnostics.filter {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        }

        #expect(generated.isEmpty)
        #expect(diagnostics.count == 3)
    }

    @Test("Conditional custom initializers in bodies and same-file extensions are rejected")
    func conditionalCustomInitializersAreRejected() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            #if DEBUG
            init(config: Config) {
                self.config = config
            }
            #endif
        }

        extension AppContainer {
            #if RELEASE
            init(config: Config, release: Bool) {
                self.init(config: config)
            }
            #endif
        }
        """

        let parsed = Parser.parse(source: source)
        let declaration = try #require(
            parsed.statements.first?.item.as(StructDeclSyntax.self)
        )
        let attribute = try #require(
            declaration.attributes.first?.as(AttributeSyntax.self)
        )
        let context = TestMacroExpansionContext()

        let generated = try DIContainerMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            in: context
        )

        #expect(generated.isEmpty)
        #expect(
            context.diagnostics.filter {
                $0.diagnosticID == MessageID(
                    domain: "InnoDI.validation",
                    id: "container.custom-init-unsupported"
                )
            }.count == 2
        )
    }

    @Test("Cross-file extension initializers are outside the current detection policy")
    func crossFileExtensionInitializersAreIgnored() throws {
        let containerSource = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config
        }
        """
        let extensionSource = """
        extension AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsedContainer = Parser.parse(source: containerSource)
        _ = Parser.parse(source: extensionSource)

        guard let decl = parsedContainer.statements.first?.item.as(StructDeclSyntax.self) else {
            Issue.record("Should parse cross-file policy fixture")
            return
        }

        let initializers = DIContainerParser.userDefinedInitializers(in: decl)
        #expect(initializers.isEmpty)
    }

    @Test("Nested same-file extensions for the annotated type are rejected")
    func nestedSameFileExtensionInitializersAreRejected() throws {
        let source = """
        struct Outer {
            @DIContainer
            struct AppContainer {
                @Provide(.input)
                var config: Config
            }
        }

        extension Outer.AppContainer {
            init(config: Config, debug: Bool) {
                self.init(config: config)
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let outerDecl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let nestedDecl = outerDecl.memberBlock.members.first?.decl.as(StructDeclSyntax.self),
              let attr = nestedDecl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse nested container")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: nestedDecl, in: context)

        #expect(generated.isEmpty)
        #expect(context.diagnostics.contains {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        })
    }

    @Test("Class, actor, and enum containers emit the declaration-kind diagnostic")
    func unsupportedNominalKindsEmitDedicatedDiagnostic() throws {
        let classDecl = try #require(
            Parser.parse(source: "@DIContainer\nclass ClassContainer {}").statements.first?
                .item.as(ClassDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            classDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ClassContainer' is declared as a class. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let actorDecl = try #require(
            Parser.parse(source: "@DIContainer\nactor ActorContainer {}").statements.first?
                .item.as(ActorDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            actorDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ActorContainer' is declared as an actor. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let enumDecl = try #require(
            Parser.parse(source: "@DIContainer\nenum EnumContainer {}").statements.first?
                .item.as(EnumDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            enumDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'EnumContainer' is declared as an enum. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let protocolDecl = try #require(
            Parser.parse(source: "@DIContainer\nprotocol ProtocolContainer {}").statements.first?
                .item.as(ProtocolDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            protocolDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ProtocolContainer' is declared as a protocol. Convert it to a struct and inject runtime state through @Provide(.input)."
        )

        let extensionDecl = try #require(
            Parser.parse(source: "@DIContainer\nextension ExtendedContainer {}").statements.first?
                .item.as(ExtensionDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            extensionDecl,
            expectedID: "container.unsupported-declaration-kind",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'ExtendedContainer' is declared as an extension. Convert it to a struct and inject runtime state through @Provide(.input)."
        )
    }

    @Test("Explicit private containers emit the access diagnostic")
    func privateContainerEmitsDedicatedDiagnostic() throws {
        let declaration = try #require(
            Parser.parse(
                source: "@DIContainer\nprivate struct PrivateContainer {}"
            ).statements.first?.item.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.private-access-unsupported",
            expectedMessage: "@DIContainer 'PrivateContainer' cannot be declared private in InnoDI 5.0 because generated child-mount APIs would not be accessible to sibling containers. Use fileprivate for file-local mounting, or place a default-access container inside a private enclosing namespace."
        )
        #expect(
            declaration.modifiers.first?.name.text == "private"
        )
    }

    @Test("Direct generic containers emit the generic diagnostic")
    func directGenericContainerEmitsDedicatedDiagnostic() throws {
        let declaration = try #require(
            Parser.parse(source: "@DIContainer\nstruct GenericContainer<Value> {}").statements.first?
                .item.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.generic-unsupported",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'GenericContainer' declares generic parameters. Move type-specific behavior behind an injected dependency."
        )
    }

    @Test("Containers nested in generic nominals emit the generic diagnostic")
    func genericOuterContainerEmitsDedicatedDiagnostic() throws {
        let outer = try #require(
            Parser.parse(
                source: "struct GenericOuter<Value> { @DIContainer struct NestedContainer {} }"
            ).statements.first?.item.as(StructDeclSyntax.self)
        )
        let declaration = try #require(
            outer.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.generic-unsupported",
            expectedMessage: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'NestedContainer' is nested in generic context 'GenericOuter<Value>'. Move type-specific behavior behind an injected dependency."
        )

        let function = try #require(
            Parser.parse(
                source: "func make() { @DIContainer struct LocalContainer {} }"
            ).statements.first?.item.as(FunctionDeclSyntax.self)
        )
        let localDeclaration = try #require(
            function.body?.statements.first?.item.as(StructDeclSyntax.self)
        )
        try assertUnsupportedContainerDeclaration(
            localDeclaration,
            expectedID: "container.local-declaration-unsupported",
            expectedMessage: "@DIContainer supports only file-scope structs or structs nested in non-generic nominal declarations in InnoDI 5.0; 'LocalContainer' is declared in an executable code scope. Move the container to file scope or a non-generic nominal declaration."
        )
    }

    @Test("Containers nested in extensions fail closed")
    func extensionNestedContainerEmitsUnverifiableContextDiagnostic() throws {
        let source = Parser.parse(
            source: "struct ExtensionOuter {}\nextension ExtensionOuter { @DIContainer struct NestedContainer {} }"
        )
        let extensionDecl = try #require(
            source.statements.last?.item.as(ExtensionDeclSyntax.self)
        )
        let declaration = try #require(
            extensionDecl.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )

        try assertUnsupportedContainerDeclaration(
            declaration,
            expectedID: "container.unverifiable-enclosing-context",
            expectedMessage: "@DIContainer cannot prove that 'NestedContainer' has a non-generic context because it is declared inside extension 'ExtensionOuter'. Move the container to file scope or a non-generic nominal declaration."
        )
    }

    @Test("Unsupported stacked container macros emit one diagnostic without companion support")
    func unsupportedStackedContainerSuppressesCompanionExpansions() {
        assertMacroExpansionInline(
            """
            @DIComponent
            @DIHierarchyRoot
            @DIContainer
            final class UnsupportedContainer {
                @Provide(.input) var config: Config
                @SubContainer(scope: .shared) var child: ChildContainer
            }
            """,
            expandedSource: """
                final class UnsupportedContainer {
                    var config: Config
                    var child: ChildContainer
                }
                """,
            diagnostics: [
                DiagnosticSpec(
                    id: MessageID(
                        domain: "InnoDI.usage",
                        id: "container.unsupported-declaration-kind"
                    ),
                    message: "@DIContainer supports only non-generic structs in InnoDI 5.0; 'UnsupportedContainer' is declared as a class. Convert it to a struct and inject runtime state through @Provide(.input).",
                    line: 3,
                    column: 1
                )
            ],
            macros: Self.macros
        )
    }

}
