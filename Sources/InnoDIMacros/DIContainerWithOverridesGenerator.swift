//
//  DIContainerWithOverridesGenerator.swift
//  InnoDIMacros
//
//  Emits the four `static func withOverrides<T>(...)` effect overloads
//  (sync / throws / async / async throws) that wrap a scoped container
//  construction + operation closure invocation. Keeping them in a dedicated
//  file makes the sub-container overrides threading and Sendable handling
//  easier to review in isolation.
//

import SwiftSyntax
import SwiftSyntaxBuilder

internal func makeWithOverridesMethods(model: DIContainerExpansionModel) -> [DeclSyntax] {
    return [
        makeWithOverridesMethod(model: model, isAsync: false, isThrowing: false),
        makeWithOverridesMethod(model: model, isAsync: false, isThrowing: true),
        makeWithOverridesMethod(model: model, isAsync: true, isThrowing: false),
        makeWithOverridesMethod(model: model, isAsync: true, isThrowing: true),
    ]
}

private func makeWithOverridesMethod(
    model: DIContainerExpansionModel,
    isAsync: Bool,
    isThrowing: Bool
) -> DeclSyntax {
    let modifiersFromAccessLevel = accessModifiers(model.accessLevel)
    var modifiers = modifiersFromAccessLevel
    modifiers.append(DeclModifierSyntax(name: .keyword(.static)))

    let inputMembers = model.inputMembers
    var params: [FunctionParameterSyntax] = []

    for member in inputMembers {
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: member.type,
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: .commaToken()
        )
        params.append(param)
    }

    let applyOverridesParam = FunctionParameterSyntax(
        firstName: .wildcardToken(),
        secondName: .identifier("applyOverrides"),
        colon: .colonToken(),
        type: TypeSyntax(stringLiteral: "(inout Overrides) -> Void"),
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: .commaToken()
    )
    params.append(applyOverridesParam)

    // operation: (Self) [async] [throws] -> T
    var operationTypeDescription = "(Self) "
    if isAsync { operationTypeDescription += "async " }
    if isThrowing { operationTypeDescription += "throws " }
    operationTypeDescription += "-> T"
    let operationParam = FunctionParameterSyntax(
        firstName: .identifier("operation"),
        secondName: nil,
        colon: .colonToken(),
        type: TypeSyntax(stringLiteral: operationTypeDescription),
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: nil
    )
    params.append(operationParam)

    // <T>
    let genericParameterClause = GenericParameterClauseSyntax(
        leftAngle: .leftAngleToken(),
        parameters: GenericParameterListSyntax([
            GenericParameterSyntax(name: .identifier("T"))
        ]),
        rightAngle: .rightAngleToken()
    )

    // `async throws` effects
    var effectSpecifiers: FunctionEffectSpecifiersSyntax? = nil
    if isAsync || isThrowing {
        effectSpecifiers = FunctionEffectSpecifiersSyntax(
            asyncSpecifier: isAsync ? .keyword(.async) : nil,
            throwsClause: isThrowing
                ? ThrowsClauseSyntax(throwsSpecifier: .keyword(.throws))
                : nil
        )
    }

    let returnClause = ReturnClauseSyntax(
        arrow: .arrowToken(),
        type: TypeSyntax(stringLiteral: "T")
    )

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params)),
        effectSpecifiers: effectSpecifiers,
        returnClause: returnClause
    )

    // Body: let container = Self(<inputs...>, applyOverrides)
    //       return [try] [await] operation(container)
    var statements: [CodeBlockItemSyntax] = []

    var callArgs: [LabeledExprSyntax] = []
    for member in inputMembers {
        callArgs.append(
            LabeledExprSyntax(
                label: .identifier(member.name),
                colon: .colonToken(),
                expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(member.name))),
                trailingComma: .commaToken()
            )
        )
    }
    callArgs.append(
        LabeledExprSyntax(
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("applyOverrides")))
        )
    )

    let selfCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.Self))),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(callArgs),
        rightParen: .rightParenToken()
    )

    let containerDecl = VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                initializer: InitializerClauseSyntax(value: selfCall)
            )
        ])
    )
    statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(containerDecl))))

    let operationCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("operation")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))))
        ]),
        rightParen: .rightParenToken()
    )
    var returnExpr: ExprSyntax = ExprSyntax(operationCall)
    if isAsync {
        returnExpr = ExprSyntax(AwaitExprSyntax(expression: returnExpr))
    }
    if isThrowing {
        returnExpr = ExprSyntax(TryExprSyntax(expression: returnExpr))
    }

    let returnStmt = ReturnStmtSyntax(expression: returnExpr)
    statements.append(CodeBlockItemSyntax(item: .stmt(StmtSyntax(returnStmt))))

    let funcDecl = FunctionDeclSyntax(
        attributes: model.options.mainActor ? mainActorAttributeList() : AttributeListSyntax([]),
        modifiers: modifiers,
        name: .identifier("withOverrides"),
        genericParameterClause: genericParameterClause,
        signature: signature,
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax(statements))
    )

    return DeclSyntax(funcDecl)
}
