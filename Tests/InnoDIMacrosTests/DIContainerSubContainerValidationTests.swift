import Foundation
import InnoDICore
import InnoDITestSupport
import SwiftParser
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Recovery ownership and final integration diagnostic contracts.
extension DIContainerMacroTests {
    @Test("SubContainer validator failures select hidden recovery support")
    func subContainerValidatorFailureSelectsRecoverySupport() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @SubContainer(scope: .shared, with: [\\.missing])
                var feature: FeatureContainer
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "sub.unknown-parent-member"
                )
            ]
        )
        #expect(
            result.expansion.contains(
                "_InnoDISubContainerAccessor(recovery: true)"
            )
        )
        #expect(
            !result.expansion.contains(
                "_InnoDISubContainerAccessor(recovery: false)"
            )
        )
        #expect(!result.expansion.contains("_storage_sub_feature"))
        #expect(!result.expansion.contains("struct Overrides"))
        #expect(!result.expansion.contains("withOverrides"))
    }

    @Test("Custom initializers preserve SubContainer source storage")
    func customInitializerPreservesSubContainerSourceStorage() {
        let result = expandMacroSource(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared, with: [])
                var feature: FeatureContainer

                init() {}
            }
            """,
            macros: Self.macros
        )

        #expect(
            result.diagnostics.map(\.diagnosticID) == [
                MessageID(
                    domain: "InnoDI.validation",
                    id: "container.custom-init-unsupported"
                )
            ]
        )
        #expect(!result.expansion.contains("_InnoDISubContainerAccessor"))
        #expect(!result.expansion.contains("_storage_sub_feature"))
        #expect(!result.expansion.contains("struct Overrides"))
        #expect(!result.expansion.contains("withOverrides"))
    }

    @Test("@SubContainer generated override slot names diagnose member collisions")
    func subContainerOverrideNameConflictDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var featureOverrides: String

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.overrides-name-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("Implicit sub-container wiring requires explicit mapping when parent has multiple candidates")
    func subContainerAmbiguousAutoWiringDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared)
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.auto-wiring-ambiguous")
            ],
            macros: Self.macros
        )
    }

    @Test("Ambiguous sub-container auto-wiring refuses a guessed fix-it")
    func subContainerAmbiguousAutoWiringRefusesFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: AppConfig
            @Provide(.shared, factory: Logger()) var logger: Logger

            @SubContainer(scope: .shared)
            var feature: FeatureContainer
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse ambiguous auto-wiring fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "sub.auto-wiring-ambiguous")
        }) else {
            Issue.record("Expected sub.auto-wiring-ambiguous diagnostic")
            return
        }

        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.isEmpty)
    }

    @Test("Explicit empty with: wiring bypasses ambiguous implicit auto-wiring")
    func subContainerExplicitEmptyWithBypassesAmbiguousAutoWiring() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig
                @Provide(.shared, factory: Logger()) var logger: Logger

                @SubContainer(scope: .shared, with: [])
                var feature: EmptyFeatureContainer
            }
            """,
            expectedCodes: [],
            macros: Self.macros
        )
    }

    @Test("`.shared` sub reading a `.transient` parent member emits sub.shared-parent-must-not-be-transient")
    func subContainerSharedParentMustNotBeTransientDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(.transient, factory: { (config: AppConfig) in Request(config: config) })
                var request: Request

                @SubContainer(scope: .shared, with: [\\.request])
                var feature: FeatureContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient")
            ],
            macros: Self.macros
        )
    }

    @Test("`.shared` sub bindings: must not target a `.transient` parent member")
    func subContainerBindingsSharedParentMustNotBeTransientDiagnoses() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @Provide(.input) var config: AppConfig

                @Provide(.transient, factory: { (config: AppConfig) in Request(config: config) })
                var request: Request

                @SubContainer(
                    scope: .shared,
                    bindings: [(child: \\.featureRequest, parent: \\.request)]
                )
                var feature: FeatureBindingsContainer
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "sub.shared-parent-must-not-be-transient")
            ],
            macros: Self.macros
        )
    }

    @Test("Sub-container-only containers still diagnose nested Overrides conflicts")
    func subContainerOnlyParentStillDiagnosesOverridesConflict() {
        assertMacroExpansionDiagnosticCodes(
            """
            @DIContainer
            struct AppContainer {
                @SubContainer(scope: .shared)
                var feature: FeatureContainer

                struct Overrides {}
            }
            """,
            expectedCodes: [
                MessageID(domain: "InnoDI.validation", id: "container.overrides-name-conflict")
            ],
            macros: Self.macros
        )
    }

    @Test("Sub-container targeting an input-only child still expands without warnings")
    func subContainerTargetingInputOnlyChildDoesNotWarn() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: AppConfig

            @SubContainer(scope: .shared)
            var feature: FeatureContainer
        }

        @DIContainer
        struct FeatureContainer {
            @Provide(.input) var config: AppConfig
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with sibling FeatureContainer")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(context.diagnostics.isEmpty)
        #expect(!generated.isEmpty)
    }

    // `provide.lazy-aliased` / `provide.provider-aliased` warn
    // when a closure parameter uses a typealias that aliases `Lazy<T>` /
    // `Provider<T>`.
    @Test("Closure parameter using a Lazy typealias emits the lazy-aliased warning")
    func lazyAliasedParameterWarns() throws {
        let source = """
        struct Config {}
        typealias SomeLazy<T> = InnoDI.Lazy<T>

        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: Config())
            var config: Config

            @Provide(.shared, factory: { (config: SomeLazy<Config>) in Service(config: config) })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: {
                  $0.item.as(StructDeclSyntax.self)?.name.text == "AppContainer"
              })?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with sibling typealias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let expectedID = MessageID(
            domain: "InnoDI.validation",
            id: "provide.lazy-aliased"
        )
        #expect(context.diagnostics.count == 1)
        #expect(context.diagnostics.first?.diagnosticID == expectedID)
    }

    @Test("Non-generic typealias for Lazy also emits the lazy-aliased warning")
    func nonGenericLazyAliasParameterWarns() throws {
        let source = """
        struct Foo {}
        typealias FooLazy = InnoDI.Lazy<Foo>

        @DIContainer
        struct AppContainer {
            @Provide(.input) var foo: Foo
            @Provide(.shared, factory: { (foo: FooLazy) in Service(fooProvider: foo) })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: {
                  $0.item.as(StructDeclSyntax.self)?.name.text == "AppContainer"
              })?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with non-generic FooLazy alias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let expectedID = MessageID(
            domain: "InnoDI.validation",
            id: "provide.lazy-aliased"
        )
        #expect(context.diagnostics.count == 1)
        #expect(context.diagnostics.first?.diagnosticID == expectedID)
    }

    @Test("Closure parameter using a Provider typealias emits the provider-aliased warning")
    func providerAliasedParameterWarns() throws {
        let source = """
        struct Config {}
        typealias SomeProvider<T> = InnoDI.Provider<T>

        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: Config

            @Provide(.transient, factory: { (config: Config) in
                Request(config: config)
            })
            var request: Request

            @Provide(.transient, factory: { (request: SomeProvider<Request>) in
                RequestLogger(provider: request)
            })
            var logger: RequestLogger
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: {
                  $0.item.as(StructDeclSyntax.self)?.name.text == "AppContainer"
              })?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with sibling typealias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        let expectedID = MessageID(
            domain: "InnoDI.validation",
            id: "provide.provider-aliased"
        )
        #expect(context.diagnostics.count == 1)
        #expect(context.diagnostics.first?.diagnosticID == expectedID)
    }

    @Test("Unrelated typealiases do not trigger the aliased warning")
    func unrelatedTypealiasDoesNotWarn() throws {
        let source = """
        typealias UserID = Int

        @DIContainer
        struct AppContainer {
            @Provide(.input) var config: AppConfig
            @Provide(.shared, factory: { (config: AppConfig) in Service(config: config) })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first(where: { $0.item.is(StructDeclSyntax.self) })?
                .item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse AppContainer with unrelated typealias")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        #expect(context.diagnostics.isEmpty)
    }

}
