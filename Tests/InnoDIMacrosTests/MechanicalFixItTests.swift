import Foundation
import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

/// Covers the mechanical fix-its attached to diagnostics whose repair is a
/// single unambiguous text edit: `some` → `any`, `T!` → `T?`,
/// `private` → `fileprivate`, and duplicate-attribute removal.
@Suite("Mechanical fix-its")
struct MechanicalFixItTests {
    private func containerDiagnostics(
        expanding source: String
    ) throws -> [Diagnostic] {
        let parsed = Parser.parse(source: source)
        guard let decl = parsed.statements.first?.item.as(StructDeclSyntax.self),
              let attribute = decl.attributes.first?.as(AttributeSyntax.self) else {
            Issue.record("Fixture should parse to an attributed struct")
            return []
        }
        let context = TestMacroExpansionContext()
        _ = try DIContainerMacro.expansion(
            of: attribute,
            providingMembersOf: decl,
            in: context
        )
        return context.diagnostics
    }

    private func messageID(_ code: InnoDIDiagnosticCode) -> MessageID {
        MessageID(
            domain: "InnoDI.\(code.category.rawValue)",
            id: code.rawValue
        )
    }

    private func replacementTexts(of diagnostic: Diagnostic) -> [String] {
        diagnostic.fixIts.flatMap(\.changes).compactMap { change in
            if case let .replaceText(_, replacementText, _) = change {
                return replacementText
            }
            return nil
        }
    }

    @Test("Opaque provider type offers a some→any replacement")
    func opaqueTypeOffersAnyReplacement() throws {
        let diagnostics = try containerDiagnostics(
            expanding: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    var service: some ServiceProtocol
                }
                """
        )
        guard let diagnostic = diagnostics.first(where: {
            $0.diagnosticID == messageID(.provideOpaqueTypeUnsupported)
        }) else {
            Issue.record("Expected provide.opaque-type-unsupported diagnostic")
            return
        }
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message == "Replace 'some' with 'any'")
        #expect(replacementTexts(of: diagnostic) == ["any"])
    }

    @Test("Implicitly unwrapped provider type offers a !→? replacement")
    func iuoTypeOffersOptionalReplacement() throws {
        let diagnostics = try containerDiagnostics(
            expanding: """
                @DIContainer
                struct AppContainer {
                    @Provide(.shared, factory: ServiceImpl())
                    var service: ServiceImpl!
                }
                """
        )
        guard let diagnostic = diagnostics.first(where: {
            $0.diagnosticID == messageID(.provideIUOTypeUnsupported)
        }) else {
            Issue.record("Expected provide.iuo-type-unsupported diagnostic")
            return
        }
        #expect(diagnostic.fixIts.count == 1)
        #expect(diagnostic.fixIts.first?.message.message == "Replace '!' with '?'")
        #expect(replacementTexts(of: diagnostic) == ["?"])
    }

    @Test("Private container offers a fileprivate replacement")
    func privateContainerOffersFileprivateReplacement() throws {
        let diagnostics = try containerDiagnostics(
            expanding: """
                @DIContainer
                private struct AppContainer {
                    @Provide(.input)
                    var config: AppConfig
                }
                """
        )
        guard let diagnostic = diagnostics.first(where: {
            $0.diagnosticID == messageID(.containerPrivateAccessUnsupported)
        }) else {
            Issue.record("Expected container.private-access-unsupported diagnostic")
            return
        }
        #expect(diagnostic.fixIts.count == 1)
        #expect(replacementTexts(of: diagnostic) == ["fileprivate"])
    }

    @Test("Duplicate @Provide offers an attribute-removal fix-it")
    func duplicateProvideOffersRemoval() throws {
        let source = """
            @Provide(.shared, factory: ServiceImpl())
            @Provide(.shared, factory: ServiceImpl())
            var service: ServiceImpl
            """
        let parsed = Parser.parse(source: source)
        guard let varDecl = parsed.statements.first?.item.as(VariableDeclSyntax.self),
              let attribute = varDecl.attributes.dropFirst().first?.as(AttributeSyntax.self) else {
            Issue.record("Fixture should parse to a doubly-attributed var")
            return
        }
        let context = TestMacroExpansionContext()
        _ = try ProvideMacro.expansion(
            of: attribute,
            providingPeersOf: varDecl,
            in: context
        )
        guard let diagnostic = context.diagnostics.first(where: {
            $0.diagnosticID == messageID(.provideDuplicateAttribute)
        }) else {
            Issue.record("Expected provide.duplicate-attribute diagnostic")
            return
        }
        #expect(diagnostic.fixIts.count == 1)
        #expect(replacementTexts(of: diagnostic) == [""])
        #expect(
            diagnostic.fixIts.first?.message.message
                == "Remove the duplicate @Provide attribute"
        )
    }
}
