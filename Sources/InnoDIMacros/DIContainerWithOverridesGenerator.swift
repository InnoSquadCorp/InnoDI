//
//  DIContainerWithOverridesGenerator.swift
//  InnoDIMacros
//
//  Emits the four `static func withOverrides<OperationResult>(...)` effect overloads
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
    if isAsync && !model.options.mainActor {
        modifiers.append(
            DeclModifierSyntax(
                name: .keyword(.nonisolated),
                detail: DeclModifierDetailSyntax(
                    detail: .identifier("nonsending")
                )
            )
        )
    }
    modifiers.append(DeclModifierSyntax(name: .keyword(.static)))

    let inputMembers = model.inputMembers
    var params: [FunctionParameterSyntax] = []

    for member in inputMembers {
        let param = FunctionParameterSyntax(
            firstName: .identifier(member.name),
            secondName: nil,
            colon: .colonToken(),
            type: inputParameterType(for: member),
            ellipsis: nil,
            defaultValue: nil,
            trailingComma: .commaToken()
        )
        params.append(param)
    }

    params.append(
        FunctionParameterSyntax(
            firstName: .identifier("_innoDITrace"),
            secondName: nil,
            colon: .colonToken(),
            type: TypeSyntax(stringLiteral: "DITraceContext"),
            ellipsis: nil,
            defaultValue: InitializerClauseSyntax(
                value: ExprSyntax(
                    MemberAccessExprSyntax(name: .identifier("disabled"))
                )
            ),
            trailingComma: .commaToken()
        )
    )

    let applyOverridesParam = FunctionParameterSyntax(
        firstName: .wildcardToken(),
        secondName: .identifier("_innoDIApplyOverrides"),
        colon: .colonToken(),
        type: overrideApplyClosureType(isMainActor: model.options.mainActor),
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: .commaToken()
    )
    params.append(applyOverridesParam)

    // operation: (Self) [async] [throws] -> OperationResult
    var operationTypeDescription: String
    if model.options.mainActor {
        operationTypeDescription = "@_Concurrency.MainActor (Self) "
    } else if isAsync {
        operationTypeDescription = "nonisolated(nonsending) (Self) "
    } else {
        operationTypeDescription = "(Self) "
    }
    if isAsync { operationTypeDescription += "async " }
    if isThrowing { operationTypeDescription += "throws " }
    operationTypeDescription += "-> OperationResult"
    let operationParam = FunctionParameterSyntax(
        firstName: .identifier("operation"),
        secondName: .identifier("_innoDIOperation"),
        colon: .colonToken(),
        type: TypeSyntax(stringLiteral: operationTypeDescription),
        ellipsis: nil,
        defaultValue: nil,
        trailingComma: nil
    )
    params.append(operationParam)

    // <OperationResult>
    let genericParameterClause = GenericParameterClauseSyntax(
        leftAngle: .leftAngleToken(),
        parameters: GenericParameterListSyntax([
            GenericParameterSyntax(name: .identifier("OperationResult"))
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
        type: TypeSyntax(stringLiteral: "OperationResult")
    )

    let signature = FunctionSignatureSyntax(
        parameterClause: FunctionParameterClauseSyntax(parameters: FunctionParameterListSyntax(params)),
        effectSpecifiers: effectSpecifiers,
        returnClause: returnClause
    )

    // Body: let _innoDIContainer = Self(<inputs...>, _innoDIApplyOverrides)
    //       return [try] [await] _innoDIOperation(_innoDIContainer)
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
            label: .identifier("_innoDITrace"),
            colon: .colonToken(),
            expression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier("_innoDITrace"))
            ),
            trailingComma: .commaToken()
        )
    )
    callArgs.append(
        LabeledExprSyntax(
            expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDIApplyOverrides")))
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
                pattern: IdentifierPatternSyntax(identifier: .identifier("_innoDIContainer")),
                initializer: InitializerClauseSyntax(value: selfCall)
            )
        ])
    )
    statements.append(CodeBlockItemSyntax(item: .decl(DeclSyntax(containerDecl))))

    let operationCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("_innoDIOperation")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_innoDIContainer"))))
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
