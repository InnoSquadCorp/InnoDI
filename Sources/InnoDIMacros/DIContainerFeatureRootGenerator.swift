import SwiftSyntax
import SwiftSyntaxBuilder

func makeFeatureRootHelperDecls(
    subContainerMembers: [SubContainerMemberModel],
    accessLevel: String?,
    isMainActor: Bool
) -> [DeclSyntax] {
    let modifiers = accessModifiers(accessLevel)

    return subContainerMembers.flatMap { member in
        member.featureRoots.flatMap { root in
            var declarations = [
                makeFeatureRootHelperDecl(
                    root: root,
                    subContainerName: member.name,
                    modifiers: modifiers,
                    isMainActor: isMainActor
                )
            ]
            if root.hosted {
                declarations.append(makeHostedFeatureRootHelperDecl(
                    root: root,
                    subContainer: member,
                    accessLevel: accessLevel
                ))
            }
            return declarations
        }
    }
}

/// Generate only on an explicit source opt-in. canImport tests module
/// availability, not visibility in this file, and must not alter generated API
/// as unrelated targets happen to build. The opting-in file imports SwiftUI
/// and InnoDISwiftUI as part of its declared source dependencies.
private func makeHostedFeatureRootHelperDecl(
    root: FeatureRootMemberModel,
    subContainer: SubContainerMemberModel,
    accessLevel: String?
) -> DeclSyntax {
    let accessPrefix = accessLevel.map { "\($0) " } ?? ""
    let childType = subContainer.type.trimmedDescription

    return DeclSyntax(
        stringLiteral: """
        @_Concurrency.MainActor
        \(accessPrefix)func \(root.helperName)<Identity>(
            identity: Identity,
            close: @escaping InnoDISwiftUI.DIContainerHostOwner<Identity, \(childType)>.Close = { _ in }
        ) -> some SwiftUI.View where Identity: Swift.Hashable & Swift.Sendable {
            InnoDISwiftUI.DIContainerHost(
                identity: identity,
                factory: { _ in self.\(subContainer.name) },
                close: close,
                content: { container, _ in
                    \(root.rootViewTypeName)(container: container)
                },
                loading: { SwiftUI.EmptyView() },
                failure: { _, _ in SwiftUI.EmptyView() }
            )
        }
        """
    )
}

private func makeFeatureRootHelperDecl(
    root: FeatureRootMemberModel,
    subContainerName: String,
    modifiers: DeclModifierListSyntax,
    isMainActor: Bool
) -> DeclSyntax {
    let rootViewCall = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(name: .keyword(.`init`)),
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
            attributes: isMainActor ? mainActorAttributeList() : AttributeListSyntax([]),
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
