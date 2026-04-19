//
//  SyntaxBuilders.swift
//  InnoDIMacros
//
//  Shared SwiftSyntaxBuilder primitives used by `DIContainerCodeGenerator` and
//  `ProvideMacro` to emit macro output directly as typed AST nodes. Prefer these
//  helpers over string-interpolated `DeclSyntax`/`StmtSyntax` literals so that
//  trivia and structure are locked in at compile time.
//
//  Note: these builders must be self-sufficient even when their output is
//  rendered via raw `.description` (e.g. from `ProvideMacro` accessor tests
//  that compare against exact strings). The AST therefore attaches explicit
//  whitespace trivia to tokens wherever the old string-parsed equivalent
//  would have produced spaces.
//

import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Local bindings

/// `let <bindingName> = <valueName>` 형태의 로컬 바인딩 DeclSyntax를
/// SwiftSyntaxBuilder로 조립한다. 문자열 interpolation 대신 AST를 직접
/// 만들어 trivia 차이를 방지한다.
internal func letBinding(name bindingName: String, value valueName: String) -> DeclSyntax {
    let valueExpr = ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(valueName)))
    return letBinding(name: bindingName, value: valueExpr)
}

/// 임의 표현식을 값으로 갖는 `let <bindingName> = <value>` 바인딩 생성.
internal func letBinding(name bindingName: String, value: ExprSyntax) -> DeclSyntax {
    DeclSyntax(
        VariableDeclSyntax(
            bindingSpecifier: .keyword(.let, trailingTrivia: .space),
            bindings: PatternBindingListSyntax([
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: .identifier(bindingName)),
                    initializer: InitializerClauseSyntax(
                        equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                        value: value
                    )
                )
            ])
        )
    )
}

// MARK: - Storage peer declarations

/// `private let <name>: <type>` (또는 `: <type>?`) 형태의 peer decl을 만든다.
/// `@Provide` 매크로가 생성하는 저장소 필드의 표준 형태.
internal func storagePeerDecl(
    name: String,
    type: TypeSyntax,
    optional: Bool
) -> DeclSyntax {
    let storedType: TypeSyntax = optional
        ? TypeSyntax(OptionalTypeSyntax(wrappedType: type.trimmed))
        : type.trimmed

    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: storedType
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

/// `private let <name>: Task<<successType>, <failureType>>` 형태의 async shared
/// 저장소 peer decl을 만든다.
internal func taskStoragePeerDecl(
    name: String,
    successType: String,
    failureType: String
) -> DeclSyntax {
    let genericClause = GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
            GenericArgumentSyntax(
                argument: .type(TypeSyntax("\(raw: successType)")),
                trailingComma: .commaToken(trailingTrivia: .space)
            ),
            GenericArgumentSyntax(argument: .type(TypeSyntax("\(raw: failureType)")))
        ])
    )
    let taskType = TypeSyntax(
        IdentifierTypeSyntax(
            name: .identifier("Task"),
            genericArgumentClause: genericClause
        )
    )

    let decl = VariableDeclSyntax(
        modifiers: DeclModifierListSyntax([
            DeclModifierSyntax(name: .keyword(.private, trailingTrivia: .space))
        ]),
        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier(name)),
                typeAnnotation: TypeAnnotationSyntax(
                    colon: .colonToken(trailingTrivia: .space),
                    type: taskType
                )
            )
        ])
    )
    return DeclSyntax(decl)
}

// MARK: - Statements

/// `return <expr>` 형태의 `CodeBlockItemSyntax`.
internal func returnStmt(expr: ExprSyntax) -> CodeBlockItemSyntax {
    let ret = ReturnStmtSyntax(
        returnKeyword: .keyword(.return, trailingTrivia: .space),
        expression: expr
    )
    return CodeBlockItemSyntax(item: .stmt(StmtSyntax(ret)))
}

/// `return [try] await <expr>` 형태의 `CodeBlockItemSyntax`.
/// `isThrowing`이 true이면 `try await`, false이면 `await`만 적용한다.
internal func awaitedReturnStmt(expr: ExprSyntax, isThrowing: Bool) -> CodeBlockItemSyntax {
    let awaited = ExprSyntax(AwaitExprSyntax(
        awaitKeyword: .keyword(.await, trailingTrivia: .space),
        expression: expr
    ))
    let wrapped: ExprSyntax = isThrowing
        ? ExprSyntax(TryExprSyntax(
            tryKeyword: .keyword(.try, trailingTrivia: .space),
            expression: awaited
        ))
        : awaited
    return returnStmt(expr: wrapped)
}

/// `if let override = <overrideName> { return override }` 형태의
/// `CodeBlockItemSyntax`. `@Provide(.transient, ...)`의 override 분기에 쓰인다.
internal func overrideCheckStmt(overrideName: String) -> CodeBlockItemSyntax {
    let ifStmt = IfExprSyntax(
        ifKeyword: .keyword(.if, trailingTrivia: .space),
        conditions: ConditionElementListSyntax([
            ConditionElementSyntax(
                condition: .optionalBinding(
                    OptionalBindingConditionSyntax(
                        bindingSpecifier: .keyword(.let, trailingTrivia: .space),
                        pattern: IdentifierPatternSyntax(
                            identifier: .identifier("override", trailingTrivia: .space)
                        ),
                        initializer: InitializerClauseSyntax(
                            equal: .equalToken(trailingTrivia: .space),
                            value: DeclReferenceExprSyntax(
                                baseName: .identifier(overrideName, trailingTrivia: .space)
                            )
                        )
                    )
                )
            )
        ]),
        body: CodeBlockSyntax(
            leftBrace: .leftBraceToken(trailingTrivia: .space),
            statements: CodeBlockItemListSyntax([
                returnStmt(expr: ExprSyntax(
                    DeclReferenceExprSyntax(
                        baseName: .identifier("override", trailingTrivia: .space)
                    )
                ))
            ]),
            rightBrace: .rightBraceToken()
        )
    )
    return CodeBlockItemSyntax(
        item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: ExprSyntax(ifStmt))))
    )
}

/// `fatalError("<message>")` 호출을 담은 `CodeBlockItemSyntax`.
internal func fatalErrorStmt(message: String) -> CodeBlockItemSyntax {
    let call = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(StringLiteralExprSyntax(content: message))
            )
        ]),
        rightParen: .rightParenToken()
    )
    return CodeBlockItemSyntax(item: .expr(ExprSyntax(call)))
}

// MARK: - Task wrapper decl

/// `let <taskName> = Task<Success, Failure> { if let override = <overrideName> { return override }; return <awaitedFactoryExpr> }`
/// 형태의 DeclSyntax를 SwiftSyntaxBuilder AST로 조립한다.
internal func makeAsyncTaskDecl(
    taskName: String,
    overrideName: String,
    successType: String,
    failureType: String,
    awaitedFactoryExpr: ExprSyntax
) -> DeclSyntax {
    // Task<Success, Failure>
    let genericClause = GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
            GenericArgumentSyntax(
                argument: .type(TypeSyntax("\(raw: successType)")),
                trailingComma: .commaToken(trailingTrivia: .space)
            ),
            GenericArgumentSyntax(argument: .type(TypeSyntax("\(raw: failureType)")))
        ])
    )
    let taskRef = GenericSpecializationExprSyntax(
        expression: DeclReferenceExprSyntax(baseName: .identifier("Task")),
        genericArgumentClause: genericClause
    )

    // Task<...> { ... }
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            overrideCheckStmt(overrideName: overrideName),
            returnStmt(expr: awaitedFactoryExpr)
        ])
    )
    let taskCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(taskRef),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )

    return letBinding(name: taskName, value: ExprSyntax(taskCall))
}
