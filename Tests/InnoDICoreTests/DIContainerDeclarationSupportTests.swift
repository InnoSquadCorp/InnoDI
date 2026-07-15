import InnoDICore
import SwiftParser
import SwiftSyntax
import Testing

@Suite("DIContainer declaration support")
struct DIContainerDeclarationSupportTests {
    @Test("Top-level and non-generic nested structs are supported")
    func supportedStructShapes() throws {
        let topLevel = try firstDeclaration(
            "@DIContainer struct AppContainer {}",
            as: StructDeclSyntax.self
        )
        #expect(classifyDIContainerDeclaration(topLevel) == .supported)

        let outer = try firstDeclaration(
            "struct Feature { @DIContainer struct Container {} }",
            as: StructDeclSyntax.self
        )
        let nested = try #require(
            outer.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        #expect(classifyDIContainerDeclaration(nested) == .supported)

        let conditionalSource = Parser.parse(source: """
            #if DEBUG
            @DIContainer struct ConditionalContainer {}
            #endif
            """)
        let conditionalCollector = DIContainerDeclarationSupportCollector()
        conditionalCollector.walk(conditionalSource)
        #expect(conditionalCollector.issues.isEmpty)

        let fileLocal = try firstDeclaration(
            "@DIContainer fileprivate struct FileLocalContainer {}",
            as: StructDeclSyntax.self
        )
        #expect(classifyDIContainerDeclaration(fileLocal) == .supported)

        let privateNamespace = try firstDeclaration(
            "private enum Namespace { @DIContainer struct Container {} }",
            as: EnumDeclSyntax.self
        )
        let effectivelyPrivateNested = try #require(
            privateNamespace.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        #expect(classifyDIContainerDeclaration(effectivelyPrivateNested) == .supported)
    }

    @Test("Explicit private access has a stable fail-closed contract")
    func privateContainerIsUnsupported() throws {
        let declaration = try firstDeclaration(
            "@DIContainer private struct PrivateContainer {}",
            as: StructDeclSyntax.self
        )
        let support = classifyDIContainerDeclaration(declaration)

        #expect(support == .privateAccess(name: "PrivateContainer"))
        #expect(support.diagnosticCode == "container.private-access-unsupported")
        #expect(
            support.diagnosticMessage
                == "@DIContainer 'PrivateContainer' cannot be declared private in InnoDI 5.0 because generated child-mount APIs would not be accessible to sibling containers. Use fileprivate for file-local mounting, or place a default-access container inside a private enclosing namespace."
        )
    }

    @Test("Every non-struct declaration kind has a stable diagnostic")
    func unsupportedDeclarationKinds() throws {
        let source = Parser.parse(source: """
            @DIContainer class ClassContainer {}
            @DIContainer actor ActorContainer {}
            @DIContainer enum EnumContainer {}
            @DIContainer protocol ProtocolContainer {}
            struct ExtendedContainer {}
            @DIContainer extension ExtendedContainer {}
            """)
        let declarations = source.statements.compactMap { statement -> (any DeclGroupSyntax)? in
            let syntax = Syntax(statement.item)
            if let declaration = syntax.as(ClassDeclSyntax.self) { return declaration }
            if let declaration = syntax.as(ActorDeclSyntax.self) { return declaration }
            if let declaration = syntax.as(EnumDeclSyntax.self) { return declaration }
            if let declaration = syntax.as(ProtocolDeclSyntax.self) { return declaration }
            if let declaration = syntax.as(ExtensionDeclSyntax.self) { return declaration }
            return nil
        }

        #expect(declarations.count == 5)
        let expected: [DIContainerDeclarationSupport] = [
            .unsupportedKind(name: "ClassContainer", kind: "class"),
            .unsupportedKind(name: "ActorContainer", kind: "actor"),
            .unsupportedKind(name: "EnumContainer", kind: "enum"),
            .unsupportedKind(name: "ProtocolContainer", kind: "protocol"),
            .unsupportedKind(name: "ExtendedContainer", kind: "extension"),
        ]
        for (declaration, expectedSupport) in zip(declarations, expected) {
            let support = classifyDIContainerDeclaration(declaration)
            #expect(support == expectedSupport)
            #expect(support.diagnosticCode == "container.unsupported-declaration-kind")
            #expect(support.diagnosticMessage?.contains("supports only non-generic structs") == true)
        }
    }

    @Test("Direct and enclosing generic declarations are rejected")
    func genericDeclarationContexts() throws {
        let direct = try firstDeclaration(
            "@DIContainer struct GenericContainer<Value> {}",
            as: StructDeclSyntax.self
        )
        #expect(
            classifyDIContainerDeclaration(direct)
                == .generic(name: "GenericContainer", contextName: nil)
        )

        let genericOuter = try firstDeclaration(
            "struct Outer<Value> { @DIContainer struct NestedContainer {} }",
            as: StructDeclSyntax.self
        )
        let nested = try #require(
            genericOuter.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        #expect(
            classifyDIContainerDeclaration(nested)
                == .generic(name: "NestedContainer", contextName: "Outer<Value>")
        )

        let function = try firstDeclaration(
            "func makeContainer<Value>() { @DIContainer struct LocalContainer {} }",
            as: FunctionDeclSyntax.self
        )
        let local = try #require(
            function.body?.statements.first?.item.as(StructDeclSyntax.self)
        )
        #expect(
            classifyDIContainerDeclaration(local)
                == .localDeclaration(
                    name: "LocalContainer",
                    context: "function 'makeContainer'"
                )
        )
    }

    @Test("Declarations in executable code scopes are rejected")
    func localDeclarationContexts() throws {
        let function = try firstDeclaration(
            "func build() { @DIContainer struct LocalContainer {} }",
            as: FunctionDeclSyntax.self
        )
        let local = try #require(
            function.body?.statements.first?.item.as(StructDeclSyntax.self)
        )
        #expect(
            classifyDIContainerDeclaration(local)
                == .localDeclaration(
                    name: "LocalContainer",
                    context: "function 'build'"
                )
        )

        let source = Parser.parse(source: """
            let closure = {
                @DIContainer struct ClosureContainer {}
            }
            struct AccessorHost {
                var value: Int {
                    @DIContainer struct AccessorContainer {}
                    return 0
                }
            }
            switch 0 {
            case 0:
                @DIContainer struct CaseContainer {}
            default:
                break
            }
            do {
                @DIContainer struct BlockContainer {}
            }
            func conditionalBuild() {
                #if DEBUG
                @DIContainer struct ConditionalLocalContainer {}
                #endif
            }
            """)
        let collector = DIContainerDeclarationSupportCollector()
        collector.walk(source)
        #expect(
            collector.issues.map(\.support) == [
                .localDeclaration(name: "ClosureContainer", context: "a closure"),
                .localDeclaration(name: "AccessorContainer", context: "an accessor"),
                .localDeclaration(name: "CaseContainer", context: "a switch case"),
                .localDeclaration(name: "BlockContainer", context: "a local code scope"),
                .localDeclaration(
                    name: "ConditionalLocalContainer",
                    context: "function 'conditionalBuild'"
                ),
            ]
        )
    }

    @Test("Extension nesting fails closed and physical parents win")
    func extensionContextFailsClosed() throws {
        let source = Parser.parse(source: """
            struct Outer {}
            extension Outer { @DIContainer struct NestedContainer {} }
            """)
        let extensionDecl = try #require(
            source.statements.last?.item.as(ExtensionDeclSyntax.self)
        )
        let nested = try #require(
            extensionDecl.memberBlock.members.first?.decl.as(StructDeclSyntax.self)
        )
        let unrelatedGenericContext = try firstDeclaration(
            "struct GenericOuter<Value> {}",
            as: StructDeclSyntax.self
        )

        #expect(
            classifyDIContainerDeclaration(
                nested,
                lexicalContext: [Syntax(unrelatedGenericContext)]
            ) == .unverifiableEnclosingContext(
                name: "NestedContainer",
                extendedType: "Outer"
            )
        )
    }

    @Test("Lexical context fallback is innermost first")
    func lexicalContextFallbackOrder() throws {
        let detached = try firstDeclaration(
            "@DIContainer struct NestedContainer {}",
            as: StructDeclSyntax.self
        )
        let inner = try firstDeclaration(
            "struct Inner<Value> {}",
            as: StructDeclSyntax.self
        )
        let outer = try firstDeclaration(
            "struct Outer<Other> {}",
            as: StructDeclSyntax.self
        )

        #expect(
            classifyDIContainerDeclaration(
                detached,
                lexicalContext: [Syntax(inner), Syntax(outer)]
            ) == .generic(name: "NestedContainer", contextName: "Inner<Value>")
        )

        let property = try firstDeclaration(
            "var value: Int { 0 }",
            as: VariableDeclSyntax.self
        )
        #expect(
            classifyDIContainerDeclaration(
                detached,
                lexicalContext: [Syntax(property)]
            ) == .localDeclaration(
                name: "NestedContainer",
                context: "an accessor or variable initializer"
            )
        )
    }

    @Test("Tree collector recognizes only InnoDI container attributes")
    func collectorAttributeIdentity() {
        let source = Parser.parse(source: """
            @InnoDI.DIContainer class QualifiedContainer {}
            @OtherDI.DIContainer class ForeignContainer {}
            @DIContainer struct SupportedContainer {}
            """)
        let collector = DIContainerDeclarationSupportCollector()
        collector.walk(source)

        #expect(collector.issues.count == 1)
        #expect(
            collector.issues.first?.support
                == .unsupportedKind(name: "QualifiedContainer", kind: "class")
        )
    }
}

private func firstDeclaration<T: DeclSyntaxProtocol>(
    _ source: String,
    as type: T.Type
) throws -> T {
    try #require(Parser.parse(source: source).statements.first?.item.as(type))
}
