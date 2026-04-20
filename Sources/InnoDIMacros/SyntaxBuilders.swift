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

// MARK: - Lazy cycle-escape helpers

/// `let _lazyCell_<name> = _LazyCell<Type>()` 형태의 로컬 바인딩을 만든다.
///
/// Phase K에서 soft-edge(Lazy<T>) 탈출구를 구현할 때 사용한다. 이 셀은
/// 생성자가 돌아가는 동안 heap-allocated 상자로 캡처되어, 나중에 target
/// 저장소가 실제 값으로 채워진 뒤에도 동일한 reference를 공유한다. `let`
/// 바인딩이므로 컨테이너 init이 끝난 후에 생성된 Lazy 래퍼가 mutable
/// capture 없이 안전하게 값을 읽을 수 있다.
internal func makeLazyCellDecl(name: String, type: TypeSyntax) -> DeclSyntax {
    let genericClause = GenericArgumentClauseSyntax(
        arguments: GenericArgumentListSyntax([
            GenericArgumentSyntax(argument: .type(type.trimmed))
        ])
    )
    let cellType = IdentifierTypeSyntax(
        name: .identifier("_LazyCell"),
        genericArgumentClause: genericClause
    )
    let initCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(
            GenericSpecializationExprSyntax(
                expression: DeclReferenceExprSyntax(baseName: .identifier("_LazyCell")),
                genericArgumentClause: genericClause
            )
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([]),
        rightParen: .rightParenToken()
    )

    _ = cellType // retained above for documentation; inferred from RHS

    let cellName = "_lazyCell_\(name)"
    return letBinding(name: cellName, value: ExprSyntax(initCall))
}

/// `_lazyCell_<name>.value = self._storage_<name>` 형태의 쓰기 표현식을 만든다.
///
/// init이 shared/input 저장소를 채운 직후에 호출되어, 미리 배포된 Lazy
/// 래퍼가 뒤늦게 해결(resolve)할 때 같은 인스턴스를 되돌려줄 수 있게 한다.
internal func makeLazyCellStoreExpr(name: String, storageName: String) -> ExprSyntax {
    let cellMember = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_lazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("value"))
    )
    let assignment = InfixOperatorExprSyntax(
        leftOperand: ExprSyntax(cellMember),
        operator: AssignmentExprSyntax(),
        rightOperand: makeSelfMemberAccessExpr(name: storageName)
    )
    return ExprSyntax(assignment)
}

/// `_lazyCell_<name>.resolver = { self.<name> }` 형태의 late-binding 표현식을 만든다.
///
/// `.transient` soft target은 init이 끝난 뒤 accessor를 통해 fresh value를
/// 다시 계산해야 하므로 concrete value를 저장하지 않고 resolver를 바인딩한다.
internal func makeLazyCellBindExpr(name: String, accessorName: String, baseName: String = "self") -> ExprSyntax {
    let resolverAccess = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_lazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("resolver"))
    )
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(makeSelfMemberAccessExpr(name: accessorName, baseName: baseName)))
        ])
    )
    let assignment = InfixOperatorExprSyntax(
        leftOperand: ExprSyntax(resolverAccess),
        operator: AssignmentExprSyntax(),
        rightOperand: ExprSyntax(closure)
    )
    return ExprSyntax(assignment)
}

/// `<Qualified>.Lazy({ _lazyCell_<name>.resolve() })` 형태의 인수 표현식을 만든다.
///
/// soft 파라미터를 감지한 factory에 넘길 값이다. Lazy 의 generic
/// 파라미터는 closure 반환 타입으로 추론되므로 `<Type>`을 명시하지 않는다.
internal func makeLazyCellWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredCellWrapperExpr(name: name, calleeDescription: calleeDescription)
}

/// `<Qualified>.Lazy({ self.<name> })` 형태의 Lazy 래퍼를 만든다.
///
/// Transient 접근자(getter) 내부에서 사용된다. getter 시점에는 `self`가
/// 완전히 초기화된 상태이므로 저장소를 init-time box 없이 직접 읽어도
/// 된다.
internal func makeLazyAccessorWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredAccessorWrapperExpr(name: name, calleeDescription: calleeDescription)
}

// MARK: - Provider wrappers (Phase L)
//
// Provider<T> 래퍼는 Lazy<T> 와 동일한 형태(closure trailing call)이지만
// 호출 시 매번 target `.transient` 저장소를 새로 resolve 한다. 생성 코드는
// 기존 `_LazyCell` 인프라를 그대로 재사용한다 — `_LazyCell.resolver` 는
// transient 대상에 대해 `{ self.<name> }` 를 바인딩해 두며, `resolve()` 는
// 매 호출마다 그 클로저를 실행해 fresh 인스턴스를 반환한다. 따라서
// Provider 용 래퍼는 "`Lazy` 대신 `Provider` 로 감쌈" 외의 차이가 없다.

/// `<Qualified>.Provider({ _lazyCell_<name>.resolve() })` 형태의 인수
/// 표현식. `.shared` init 경로에서 `Provider<T>` 파라미터에 주입된다.
internal func makeProviderCellWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredCellWrapperExpr(name: name, calleeDescription: calleeDescription)
}

/// `<Qualified>.Provider({ self.<name> })` 형태의 Provider 래퍼. transient
/// 접근자 내부에서 사용된다 (`self` 이미 초기화 완료).
internal func makeProviderAccessorWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredAccessorWrapperExpr(name: name, calleeDescription: calleeDescription)
}

/// `_<lazyCell>.resolve()` 기반 deferred wrapper 표현식을 만든다.
private func makeDeferredCellWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeLazyCellWrapperExprCore(name: name, calleeDescription: calleeDescription)
}

/// `self.<name>` 기반 deferred wrapper 표현식을 만든다.
private func makeDeferredAccessorWrapperExpr(name: String, calleeDescription: String) -> ExprSyntax {
    makeDeferredWrapperExpr(calleeDescription: calleeDescription, resolverExpression: makeSelfMemberAccessExpr(name: name))
}

/// `makeDeferredCellWrapperExpr` 본체를 Lazy / Provider 양쪽에서 공유할 수
/// 있도록 분리한 내부 구현. 호출처는 `calleeDescription` 으로 래퍼 이름
/// ("Lazy" / "Provider" / "InnoDI.Lazy" 등)을 결정한다.
private func makeLazyCellWrapperExprCore(name: String, calleeDescription: String) -> ExprSyntax {
    let resolveAccess = MemberAccessExprSyntax(
        base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("_lazyCell_\(name)"))),
        declName: DeclReferenceExprSyntax(baseName: .identifier("resolve"))
    )
    let resolveCall = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(resolveAccess),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([]),
        rightParen: .rightParenToken()
    )
    return makeDeferredWrapperExpr(calleeDescription: calleeDescription, resolverExpression: ExprSyntax(resolveCall))
}

private func makeDeferredWrapperExpr(calleeDescription: String, resolverExpression: ExprSyntax) -> ExprSyntax {
    let closure = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(resolverExpression))
        ])
    )
    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax("\(raw: calleeDescription)"),
        leftParen: nil,
        arguments: LabeledExprListSyntax([]),
        rightParen: nil,
        trailingClosure: closure
    )
    return ExprSyntax(call)
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
