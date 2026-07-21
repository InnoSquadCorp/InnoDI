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
    @Test("Factory parameter diagnostics include notes and a unique rename fix-it")
    func unresolvedFactoryParameterDiagnosticsIncludeRenameFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var baseURL: String

            @Provide(.shared, factory: { (base_url: String) in
                Service(baseURL: base_url)
            })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(!diagnostic.notes.isEmpty)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("baseURL") == true)
    }

    @Test("Factory parameter diagnostics suggest a typo fix-it when only a Damerau-Levenshtein match exists")
    func unresolvedFactoryParameterDiagnosticsIncludeTypoFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var apiClient: APIClient

            @Provide(.shared, factory: { (apiClent: APIClient) in
                Service(client: apiClent)
            })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse typo unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("apiClient") == true)
    }

    @Test("Factory parameter diagnostics omit a fix-it when no member is within typo distance")
    func unresolvedFactoryParameterDiagnosticsHaveNoFixItForFarMisses() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var apiClient: APIClient

            @Provide(.shared, factory: { (totallyDifferent: APIClient) in
                Service(client: totallyDifferent)
            })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse far-miss unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(diagnostic.fixIts.isEmpty)
    }

    @Test("Factory parameter diagnostics skip fix-its when multiple candidates exist")
    func unresolvedFactoryParameterDiagnosticsSkipAmbiguousFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var apiClient: APIClient

            @Provide(.input)
            var api_client: APIClient

            @Provide(.shared, factory: { (apiclient: APIClient) in
                Service(client: apiclient)
            })
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse ambiguous unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(diagnostic.notes.count == 2)
        #expect(diagnostic.fixIts.isEmpty)
    }


    @Test("Factory parameter diagnostics suppress fix-its for declaration-order unavailable shared candidates")
    func unresolvedFactoryParameterDiagnosticsSkipUnavailableFixItForSharedMember() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (later_service: LaterService) in
                Service(laterService: later_service)
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse declaration-order unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains(where: { $0.message.contains("declaration order") }))
    }

    @Test("Factory parameter diagnostics keep fix-its for async shared members that can see later sync shared dependencies")
    func unresolvedFactoryParameterDiagnosticsIncludeFixItForAsyncSharedLaterSyncDependency() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, asyncFactory: { (later_service: LaterService) async in
                Service(laterService: later_service)
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse async shared unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("laterService") == true)
    }

    @Test("Factory parameter diagnostics keep fix-its for transient members that can see later dependencies")
    func unresolvedFactoryParameterDiagnosticsIncludeFixItForTransientLaterDependency() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.transient, factory: { (later_service: LaterService) in
                Service(laterService: later_service)
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse transient unresolved factory parameter fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-factory-parameter")
        }) else {
            Issue.record("Expected unresolved factory parameter diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("laterService") == true)
    }

    @Test("with dependency diagnostics include notes and a unique replacement fix-it")
    func unresolvedWithDependencyDiagnosticsIncludeReplacementFixIt() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var baseURL: String

            @Provide(.shared, Service.self, with: [\\Self.base_url])
            var service: Service
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unresolved with dependency fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")
        }) else {
            Issue.record("Expected unresolved with dependency diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(!diagnostic.notes.isEmpty)
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message.contains("\\.baseURL") == true)
    }

    @Test("with dependency diagnostics suppress fix-its for declaration-order unavailable shared candidates")
    func unresolvedWithDependencyDiagnosticsSkipUnavailableFixItForSharedMember() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, Service.self, with: [\\Self.later_service])
            var service: Service

            @Provide(.shared, factory: LaterService())
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse declaration-order unresolved with dependency fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unresolved-with-dependency")
        }) else {
            Issue.record("Expected unresolved with dependency diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(diagnostic.fixIts.isEmpty)
        #expect(diagnostic.notes.contains(where: { $0.message.contains("declaration order") }))
    }

    @Test("Unavailable dependency diagnostics explain declaration-order constraints")
    func unavailableDependencyDiagnosticsIncludeNotes() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.shared, factory: { (laterService: LaterService) in
                Service(laterService: laterService)
            })
            var service: Service

            @Provide(.shared, factory: LaterService())
            var laterService: LaterService
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse unavailable dependency fixture")
            return
        }

        let context = TestMacroExpansionContext()
        let generated = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "provide.unavailable-dependency-reference")
        }) else {
            Issue.record("Expected unavailable dependency diagnostic")
            return
        }

        #expect(generated.isEmpty)
        #expect(!diagnostic.notes.isEmpty)
        #expect(diagnostic.fixIts.isEmpty)
    }

    @Test("Custom init diagnostics include guidance notes and no fix-it")
    func customInitDiagnosticsIncludeGuidanceNotes() throws {
        let source = """
        @DIContainer
        struct AppContainer {
            @Provide(.input)
            var config: Config

            init(config: Config) {
                self.config = config
            }
        }
        """

        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attr = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Should parse custom init guidance fixture")
            return
        }

        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(of: attr, providingMembersOf: decl, in: context)

        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == MessageID(domain: "InnoDI.validation", id: "container.custom-init-unsupported")
        }) else {
            Issue.record("Expected custom init diagnostic")
            return
        }

        #expect(diagnostic.notes.count == 2)
        #expect(diagnostic.fixIts.isEmpty)
    }
}
