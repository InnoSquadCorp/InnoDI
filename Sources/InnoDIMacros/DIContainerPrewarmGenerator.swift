import SwiftSyntax
import SwiftSyntaxBuilder

/// Use the existing compiler-owned namespace without shadowing ordinary
/// payload types named `PrewarmProvider`. No natural-name alias is emitted.
private let prewarmProviderTypeName = "_InnoDIPrewarmProvider"

/// A selection-only API: cases carry neither values nor resolver closures.
/// A single typed variadic replaces the runtime-checked key-path overload.
/// Dispatch is once per selection; an empty selection is a nonthrowing no-op.
func makeTypedPrewarmDecls(model: DIContainerExpansionModel) -> [DeclSyntax] {
    let members = model.syncSharedMembers.filter { $0.initialization == .onDemand }
    guard !members.isEmpty else { return [] }

    let selectionType = TypeSyntax(IdentifierTypeSyntax(name: .identifier(prewarmProviderTypeName)))
    let selectionEnum = EnumDeclSyntax(
        modifiers: accessModifiers(model.accessLevel),
        name: .identifier(prewarmProviderTypeName),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(type: TypeSyntax("Swift.Sendable"))
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax(members.map { member in
                MemberBlockItemSyntax(decl: EnumCaseDeclSyntax(
                    elements: EnumCaseElementListSyntax([
                        EnumCaseElementSyntax(name: .identifier(member.name))
                    ])
                ))
            })
        )
    )

    let cases = members.map { member in
        SwitchCaseListSyntax.Element.switchCase(SwitchCaseSyntax(
            label: .case(SwitchCaseLabelSyntax(caseItems: SwitchCaseItemListSyntax([
                SwitchCaseItemSyntax(pattern: ExpressionPatternSyntax(
                    expression: MemberAccessExprSyntax(name: .identifier(member.name))
                ))
            ]))),
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(item: .expr(ExprSyntax(InfixOperatorExprSyntax(
                    leftOperand: DiscardAssignmentExprSyntax(),
                    operator: AssignmentExprSyntax(),
                    rightOperand: makeSelfMemberAccessExpr(name: member.name)
                ))))
            ])
        ))
    }
    let prewarm = FunctionDeclSyntax(
        attributes: model.options.mainActor ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: accessModifiers(model.accessLevel),
        name: .identifier("prewarm"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax([
                FunctionParameterSyntax(
                    firstName: .wildcardToken(),
                    secondName: .identifier("providers"),
                    type: selectionType,
                    ellipsis: .ellipsisToken()
                )
            ]))
        ),
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .stmt(StmtSyntax(ForStmtSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("provider")),
                sequence: DeclReferenceExprSyntax(baseName: .identifier("providers")),
                body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: .expr(ExprSyntax(SwitchExprSyntax(
                        subject: DeclReferenceExprSyntax(baseName: .identifier("provider")),
                        cases: SwitchCaseListSyntax(cases)
                    ))))
                ]))
            ))))
        ]))
    )

    return [DeclSyntax(selectionEnum), DeclSyntax(prewarm)]
}
