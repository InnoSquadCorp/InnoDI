import SwiftSyntax
import SwiftSyntaxBuilder

func makeFeatureRootHelperDecls(
    subContainerMembers: [SubContainerMemberModel],
    accessLevel: String?
) -> [DeclSyntax] {
    let modifiers = accessModifiers(accessLevel)

    return subContainerMembers.flatMap { member in
        member.featureRoots.map { root in
            makeFeatureRootHelperDecl(
                root: root,
                subContainerName: member.name,
                modifiers: modifiers
            )
        }
    }
}

private func makeFeatureRootHelperDecl(
    root: FeatureRootMemberModel,
    subContainerName: String,
    modifiers: DeclModifierListSyntax
) -> DeclSyntax {
    let rootViewCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax("\(raw: root.rootViewTypeName)"),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                label: .identifier("container"),
                colon: .colonToken(),
                expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(subContainerName)))
            )
        ]),
        rightParen: .rightParenToken()
    )

    return DeclSyntax(
        FunctionDeclSyntax(
            modifiers: modifiers,
            name: .identifier(root.helperName),
            signature: FunctionSignatureSyntax(
                parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax([])),
                returnClause: ReturnClauseSyntax(type: TypeSyntax("\(raw: root.rootViewTypeName)"))
            ),
            body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(ExprSyntax(rootViewCall)))
            ]))
        )
    )
}
