import InnoDICore
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
                declarations.append(contentsOf: makeHostedFeatureRootHelperDecls(
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
///
/// A `.transient` child is host-owned: the factory builds one child per
/// identity after mount and the close hook ends that child. A `.shared` child
/// belongs to the parent, which built it at initialization and keeps serving
/// it, so the host only presents it and has nothing to close. Its overload
/// therefore takes no close hook. The 7.0 `identity:close:` spelling stays
/// available, unchanged, for source compatibility; it is deprecated because
/// it hands the parent's instance to the hook at every identity change and
/// explicit close while the parent continues to serve it.
private func makeHostedFeatureRootHelperDecls(
    root: FeatureRootMemberModel,
    subContainer: SubContainerMemberModel,
    accessLevel: String?
) -> [DeclSyntax] {
    guard subContainer.scope == .shared else {
        return [makeHostedFeatureRootHelperDecl(
            root: root,
            subContainer: subContainer,
            accessLevel: accessLevel,
            closeParameter: .defaulted
        )]
    }
    return [
        makeHostedFeatureRootHelperDecl(
            root: root,
            subContainer: subContainer,
            accessLevel: accessLevel,
            closeParameter: .none
        ),
        makeHostedFeatureRootHelperDecl(
            root: root,
            subContainer: subContainer,
            accessLevel: accessLevel,
            closeParameter: .deprecatedForSharedChild
        ),
    ]
}

private enum HostedFeatureRootCloseParameter {
    /// `close:` with a no-op default; the host owns each generation.
    case defaulted
    /// No `close:`; the host presents a parent-owned child.
    case none
    /// Required `close:`, deprecated: the hook receives a parent-owned child.
    case deprecatedForSharedChild
}

private func makeHostedFeatureRootHelperDecl(
    root: FeatureRootMemberModel,
    subContainer: SubContainerMemberModel,
    accessLevel: String?,
    closeParameter: HostedFeatureRootCloseParameter
) -> DeclSyntax {
    let accessPrefix = accessLevel.map { "\($0) " } ?? ""
    let childType = subContainer.type.trimmedDescription
    let closeType = "InnoDISwiftUI.DIContainerHostOwner<_InnoDIIdentity, \(childType)>.Close"

    let availability: String
    let closeSignature: String
    let closeArgument: String
    switch closeParameter {
    case .defaulted:
        availability = ""
        closeSignature = ",\n    close: @escaping \(closeType) = { _ in }"
        closeArgument = "\n        close: close,"
    case .none:
        availability = ""
        closeSignature = ""
        closeArgument = ""
    case .deprecatedForSharedChild:
        let message = sharedHostedFeatureRootCloseDeprecationMessage(
            helperName: root.helperName,
            propertyName: subContainer.name
        )
        availability = "@available(*, deprecated, message: \"\(message)\")\n"
        closeSignature = ",\n    close: @escaping \(closeType)"
        closeArgument = "\n        close: close,"
    }

    // The generic parameter shares this signature with the child and root
    // view type spellings, so a source name such as `Identity` would shadow a
    // user type of that name. Callers never spell it.
    return DeclSyntax(
        stringLiteral: """
        \(availability)@_Concurrency.MainActor
        \(accessPrefix)func \(root.helperName)<_InnoDIIdentity>(
            identity: _InnoDIIdentity\(closeSignature)
        ) -> some SwiftUI.View where _InnoDIIdentity: Swift.Hashable & Swift.Sendable {
            InnoDISwiftUI.DIContainerHost(
                identity: identity,
                factory: { _ in self.\(subContainer.name) },\(closeArgument)
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

/// Plain text only: the message is spliced into a string literal.
func sharedHostedFeatureRootCloseDeprecationMessage(
    helperName: String,
    propertyName: String
) -> String {
    "'\(propertyName)' is a .shared child: the parent built it at initialization and keeps serving it, "
        + "so the host does not own it, yet this close hook receives that same instance at every identity change "
        + "and explicit close. Call \(helperName)(identity:) without close:, or declare the child "
        + "@SubContainer(scope: .transient) so the host creates and closes one child per identity."
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
