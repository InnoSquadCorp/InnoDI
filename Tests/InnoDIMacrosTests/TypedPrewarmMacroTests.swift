import InnoDITestSupport
import SwiftDiagnostics
import SwiftParser
import SwiftSyntax
import SwiftSyntaxMacros
import Testing

@testable import InnoDIMacros

@Suite("Typed synchronous prewarm generation")
struct TypedPrewarmMacroTests {
    private static var macros: [String: any Macro.Type] {
        var result = DIContainerMacroTests.macros
        result["DIContainerRole"] = DIContainerRoleMacro.self
        return result
    }

    @Test("Selection cases contain only synchronous on-demand shared providers")
    func selectionScopes() throws {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                @Input var input: Int
                @Provide(.shared, factory: 1) var eager: Int
                @Provide(.shared, initialization: .onDemand, factory: 2) var selected: Int
                @Provide(.transient, factory: 3) var transient: Int
                @Provide(.shared, asyncFactory: { () async in 4 }) var asynchronous: Int
                @Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 5 }) var asyncOnDemand: Int
                @Provide(.shared, initialization: .onDemand, factory: 6) var last: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        let container = try parsedContainer(in: result.expansion)
        let selection = try #require(container.memberBlock.members.compactMap {
            $0.decl.as(EnumDeclSyntax.self)
        }.first { $0.name.text == "_InnoDIPrewarmProvider" })
        #expect(selection.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription == "Swift.Sendable")
        #expect(selection.memberBlock.members.compactMap {
            $0.decl.as(EnumCaseDeclSyntax.self)?.elements.first?.name.text
        } == ["selected", "last"])
        #expect(selection.memberBlock.members.count == 2)
        #expect(!result.expansion.contains("@unchecked"))
    }

    @Test("Accepted contextual and Unicode provider names are preserved as enum cases", arguments: [
        "some", "any", "actor", "nonisolated", "package", "서비스",
    ])
    func acceptedProviderIdentifiers(_ name: String) throws {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                @Provide(.shared, initialization: .onDemand, factory: 1) var \(name): Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        let selection = try #require(try parsedContainer(in: result.expansion).memberBlock.members.compactMap {
            $0.decl.as(EnumDeclSyntax.self)
        }.first)
        #expect(selection.memberBlock.members.first?.decl.as(EnumCaseDeclSyntax.self)?.elements.first?.name.text == name)
        #expect(result.expansion.contains("case .\(name):"))
        #expect(result.expansion.contains("_ = self.\(name)"))
    }

    @Test("Typed dispatch visits each selected token once without a key-path fallback")
    func directDispatchShape() throws {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                @Provide(.shared, initialization: .onDemand, factory: 1) var first: Int
                @Provide(.shared, initialization: .onDemand, factory: 2) var second: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        let methods = try parsedContainer(in: result.expansion).memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }
        let typed = try #require(methods.first {
            $0.name.text == "prewarm"
                && $0.signature.parameterClause.parameters.first?.type.trimmedDescription == "_InnoDIPrewarmProvider"
        })
        #expect(typed.signature.effectSpecifiers == nil)
        #expect(typed.signature.parameterClause.parameters.count == 1)
        #expect(typed.signature.parameterClause.parameters.first?.ellipsis != nil)
        #expect(typed.body?.trimmedDescription.filter { !$0.isWhitespace } == """
            {
                for provider in providers {
                    switch provider {
                    case .first:
                        _ = self.first
                    case .second:
                        _ = self.second
                    }
                }
            }
            """.filter { !$0.isWhitespace })
        #expect(methods.filter { $0.name.text == "prewarm" }.count == 1)
        #expect(!result.expansion.contains("Swift.PartialKeyPath<Self>"))
        #expect(!result.expansion.contains("func _innoDIPrewarm"))

    }

    @Test("The selection type and method follow container visibility", arguments: [
        "", "public", "package", "internal", "fileprivate",
    ])
    func visibility(_ access: String) throws {
        let result = expandMacroSource("""
            @DIContainer \(access) struct Container {
                @Provide(.shared, initialization: .onDemand, factory: 1) var service: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        let members = try parsedContainer(in: result.expansion).memberBlock.members
        let selection = try #require(members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.first)
        let method = try #require(members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }.first {
            $0.name.text == "prewarm"
                && $0.signature.parameterClause.parameters.count == 1
        })
        #expect((selection.modifiers.first?.name.text ?? "") == access)
        #expect((method.modifiers.first?.name.text ?? "") == access)
    }

    @Test("MainActor protects prewarming")
    func mainActorIsolation() throws {
        let result = expandMacroSource("""
            @DIContainerRole(role: ContainerRole.local, mainActor: true)
            struct Container {
                @Provide(.shared, initialization: .onDemand, factory: NonSendable()) var service: NonSendable
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        let methods = try parsedContainer(in: result.expansion).memberBlock.members.compactMap {
            $0.decl.as(FunctionDeclSyntax.self)
        }.filter { ["prewarm", "_innoDIPrewarm"].contains($0.name.text) }
        #expect(methods.count == 1)
        #expect(methods.allSatisfy {
            $0.attributes.contains {
                $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription.hasSuffix("MainActor") == true
            }
        })
        #expect(!result.expansion.contains("@unchecked"))
    }

    @Test("Containers without eligible providers synthesize no selection type", arguments: [
        "", "@Input var input: Int", "@Provide(.shared, factory: 1) var service: Int",
        "@Provide(.transient, factory: 1) var service: Int",
        "@Provide(.shared, initialization: .onDemand, asyncFactory: { () async in 1 }) var service: Int",
    ])
    func noEligibleProviders(_ members: String) {
        let result = expandMacroSource("@DIContainer struct Container { \(members) }", macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        #expect(!result.expansion.contains("enum _InnoDIPrewarmProvider"))
        #expect(!result.expansion.contains("func _innoDIPrewarm"))
    }

    @Test("Compiler-owned selection names use the existing reserved-prefix diagnostic", arguments: [
        "struct _InnoDIPrewarmProvider {}", "enum _InnoDIPrewarmProvider {}", "class _InnoDIPrewarmProvider {}",
        "typealias _InnoDIPrewarmProvider = Int", "#if DEBUG\nstruct _InnoDIPrewarmProvider {}\n#endif",
    ])
    func anchoredTypeNameCollision(_ declaration: String) {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                @Provide(.shared, initialization: .onDemand, factory: 1) var service: Int
                \(declaration)
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [InnoDIDiagnosticCode.containerReservedNamePrefix.messageID])
        #expect(result.diagnostics.first?.node.trimmedDescription == "_InnoDIPrewarmProvider")
        #expect(!result.expansion.contains("enum _InnoDIPrewarmProvider: Swift.Sendable"))
    }

    @Test("An ordinary nested payload type named PrewarmProvider remains available")
    func nestedPayloadTypeNameAllowed() {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                enum PrewarmProvider { case service }
                @Provide(.shared, initialization: .onDemand, factory: PrewarmProvider.service)
                var service: PrewarmProvider
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
    }

    @Test("An ordinary input named PrewarmProvider remains available")
    func valueNameAllowed() {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                @Input var PrewarmProvider: Int
                @Provide(.shared, initialization: .onDemand, factory: 1) var service: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("enum _InnoDIPrewarmProvider: Swift.Sendable"))
    }

    @Test("Direct Swift type shadows are diagnosed for typed prewarm")
    func directSwiftTypeShadow() {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                struct Swift {}
                @Provide(.shared, initialization: .onDemand, factory: 1) var service: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [InnoDIDiagnosticCode.containerReservedModuleName.messageID])
        #expect(result.diagnostics.first?.node.trimmedDescription == "Swift")
    }

    @Test("An enclosing nominal Swift cannot shadow typed prewarm's qualifier")
    func enclosingSwiftTypeShadow() {
        let result = expandMacroSource("""
            struct Swift {
                @DIContainer struct Container {
                    @Provide(.shared, initialization: .onDemand, factory: 1) var service: Int
                }
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.map(\.diagnosticID) == [InnoDIDiagnosticCode.containerReservedModuleName.messageID])
    }

    @Test("Unrelated nested Swift types and safe value names remain available")
    func unrelatedSwiftNamesAllowed() {
        let result = expandMacroSource("""
            @DIContainer struct Container {
                @Input var Swift: Int
                struct Unrelated { struct Swift {} }
                @Provide(.shared, initialization: .onDemand, factory: 1) var service: Int
            }
            """, macros: Self.macros)
        #expect(result.diagnostics.isEmpty)
        #expect(result.expansion.contains("enum _InnoDIPrewarmProvider: Swift.Sendable"))
    }

    private func parsedContainer(in expansion: String) throws -> StructDeclSyntax {
        try #require(Parser.parse(source: expansion).statements.first?.item.as(StructDeclSyntax.self))
    }
}
