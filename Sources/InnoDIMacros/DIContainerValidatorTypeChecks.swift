//
//  DIContainerValidatorTypeChecks.swift
//  InnoDIMacros
//
//  Type-level helpers the validator leans on when deciding whether a
//  `@Provide`d member needs `concrete: true`, when normalizing optional /
//  tuple / attributed wrappers, and when detecting async closures. Pulling
//  these out keeps `DIContainerValidator.swift` focused on the per-member
//  validation loop itself.
//

import SwiftSyntax

internal func requiresConcreteOptIn(type: TypeSyntax) -> Bool {
    let normalized = normalizedConcreteCheckType(type)

    if normalized.is(SomeOrAnyTypeSyntax.self) || normalized.is(CompositionTypeSyntax.self) {
        return false
    }

    if let identifier = normalized.as(IdentifierTypeSyntax.self) {
        return !isExistentialIdentifier(identifier.name.text)
    }

    if let member = normalized.as(MemberTypeSyntax.self) {
        return !isExistentialIdentifier(member.name.text)
    }

    return true
}

private func normalizedConcreteCheckType(_ type: TypeSyntax) -> TypeSyntax {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return normalizedConcreteCheckType(optional.wrappedType)
    }

    if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return normalizedConcreteCheckType(implicitlyUnwrapped.wrappedType)
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedConcreteCheckType(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return normalizedConcreteCheckType(first.type)
    }

    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == "Optional",
       let wrapped = identifier.genericArgumentClause?.arguments.first?.argument,
       let wrappedType = wrapped.as(TypeSyntax.self) {
        return normalizedConcreteCheckType(wrappedType)
    }

    return type
}

private func isExistentialIdentifier(_ name: String) -> Bool {
    name == "Any" || name == "AnyObject"
}

internal func isAsyncClosureExpression(_ expr: ExprSyntax) -> Bool {
    guard let closure = expr.as(ClosureExprSyntax.self) else {
        return false
    }
    return closure.signature?.effectSpecifiers?.asyncSpecifier != nil
}

internal func isThrowingClosureExpression(_ expr: ExprSyntax) -> Bool {
    guard let closure = expr.as(ClosureExprSyntax.self) else {
        return false
    }
    return closure.signature?.effectSpecifiers?.throwsClause != nil
}

internal func factoryExpressionContainsAwait(_ expr: ExprSyntax) -> Bool {
    let visitor = FactoryEffectVisitor(rootClosure: expr.as(ClosureExprSyntax.self))
    visitor.walk(Syntax(expr))
    return visitor.containsAwait
}

internal func factoryExpressionContainsPlainTry(_ expr: ExprSyntax) -> Bool {
    let visitor = FactoryEffectVisitor(rootClosure: expr.as(ClosureExprSyntax.self))
    visitor.walk(Syntax(expr))
    return visitor.containsPlainTry
}

private final class FactoryEffectVisitor: SyntaxVisitor {
    let rootClosurePosition: AbsolutePosition?
    var containsAwait = false
    var containsPlainTry = false
    private var handledThrowDepth = 0
    private var catchClauseHandledAdjustments: [Bool] = []

    init(rootClosure: ClosureExprSyntax?) {
        self.rootClosurePosition = rootClosure?.position
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: AwaitExprSyntax) -> SyntaxVisitorContinueKind {
        containsAwait = true
        return .skipChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark == nil && handledThrowDepth == 0 {
            containsPlainTry = true
        }
        return .visitChildren
    }

    override func visit(_ node: DoStmtSyntax) -> SyntaxVisitorContinueKind {
        if hasCatchAll(node.catchClauses) {
            handledThrowDepth += 1
        }
        return .visitChildren
    }

    override func visitPost(_ node: DoStmtSyntax) {
        if hasCatchAll(node.catchClauses) {
            handledThrowDepth -= 1
        }
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        let adjusted = handledThrowDepth > 0
        if adjusted {
            handledThrowDepth -= 1
        }
        catchClauseHandledAdjustments.append(adjusted)
        return .visitChildren
    }

    override func visitPost(_ node: CatchClauseSyntax) {
        let adjusted = catchClauseHandledAdjustments.removeLast()
        if adjusted {
            handledThrowDepth += 1
        }
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if let rootClosurePosition, node.position == rootClosurePosition {
            return .visitChildren
        }
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}

private func hasCatchAll(_ catchClauses: CatchClauseListSyntax) -> Bool {
    catchClauses.contains { $0.catchItems.isEmpty }
}
