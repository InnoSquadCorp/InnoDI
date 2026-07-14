import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension DIContainerDeclarationSupport {
    func diagnose(
        at attribute: AttributeSyntax,
        in context: some MacroExpansionContext
    ) {
        switch self {
        case .supported:
            return
        case let .unsupportedKind(name, kind):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerUnsupportedDeclarationKind(
                        name: name,
                        kind: kind
                    )
                )
            )
        case let .generic(name, contextName):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerGenericUnsupported(
                        name: name,
                        contextName: contextName
                    )
                )
            )
        case let .unverifiableEnclosingContext(name, extendedType):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerUnverifiableEnclosingContext(
                        name: name,
                        extendedType: extendedType
                    )
                )
            )
        case let .localDeclaration(name, localContext):
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.containerLocalDeclarationUnsupported(
                        name: name,
                        context: localContext
                    )
                )
            )
        }
    }
}

/// Accessor macros must always emit a non-observing accessor. When the owning
/// container has already failed the 5.0 declaration-shape check, this recovery
/// getter keeps the compiler from adding a second structural macro error. The
/// primary `@DIContainer` diagnostic makes the expansion unbuildable, so the
/// body cannot reach runtime.
func unsupportedDIContainerRecoveryAccessor() -> AccessorDeclSyntax {
    let failure = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(
            base: DeclReferenceExprSyntax(baseName: .identifier("Swift")),
            period: .periodToken(),
            declName: DeclReferenceExprSyntax(
                baseName: .identifier("preconditionFailure")
            )
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(
                    StringLiteralExprSyntax(
                        content: "Unsupported @DIContainer declaration"
                    )
                )
            )
        ]),
        rightParen: .rightParenToken()
    )
    return AccessorDeclSyntax(
        accessorSpecifier: .keyword(.get),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(ExprSyntax(failure)))
            ])
        )
    )
}

func isEnclosedByUnsupportedDIContainer(
    _ declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
) -> Bool {
    guard let container = enclosingDIContainerDeclaration(
        startingAt: Syntax(declaration),
        lexicalContext: context.lexicalContext
    ) else {
        return false
    }

    return !classifyDIContainerDeclaration(
        container,
        lexicalContext: context.lexicalContext
    ).isSupported
}

func isSupportedDIContainerDeclarationIfPresent(
    _ declaration: some DeclGroupSyntax,
    in context: some MacroExpansionContext
) -> Bool {
    guard findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) != nil else {
        return true
    }

    return classifyDIContainerDeclaration(
        declaration,
        lexicalContext: context.lexicalContext
    ).isSupported
}

private func enclosingDIContainerDeclaration(
    startingAt syntax: Syntax,
    lexicalContext: [Syntax]
) -> (any DeclGroupSyntax)? {
    var current: Syntax? = syntax.parent
    while let node = current {
        if let declaration = diContainerDeclGroup(from: node),
           findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) != nil {
            return declaration
        }
        current = node.parent
    }

    for node in lexicalContext {
        if let declaration = diContainerDeclGroup(from: node),
           findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) != nil {
            return declaration
        }
    }

    return nil
}

private func diContainerDeclGroup(from syntax: Syntax) -> (any DeclGroupSyntax)? {
    if let declaration = syntax.as(StructDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ClassDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ActorDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(EnumDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ProtocolDeclSyntax.self) {
        return declaration
    }
    if let declaration = syntax.as(ExtensionDeclSyntax.self) {
        return declaration
    }
    return nil
}
