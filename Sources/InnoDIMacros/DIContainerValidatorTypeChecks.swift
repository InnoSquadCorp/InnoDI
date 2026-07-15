//
//  DIContainerValidatorTypeChecks.swift
//  InnoDIMacros
//
//  Type-level helpers the validator leans on when normalizing optional /
//  tuple / attributed wrappers and when detecting async closures. Pulling
//  these out keeps `DIContainerValidator.swift` focused on the per-member
//  validation loop itself.
//

import SwiftSyntax

/// Opaque property types cannot be reproduced in InnoDI's optional backing
/// slot or `Overrides` surface because `nil` provides no concrete underlying
/// type for `some P`. InnoDI 5.0 rejects them and asks callers to expose an
/// existential (`any P`) instead.
internal func isOpaqueSomeType(_ type: TypeSyntax) -> Bool {
    guard let someOrAny = normalizedProviderType(type).as(SomeOrAnyTypeSyntax.self) else {
        return false
    }
    return someOrAny.someOrAnySpecifier.tokenKind == .keyword(.some)
}

internal func isImplicitlyUnwrappedOptionalType(_ type: TypeSyntax) -> Bool {
    type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
}

/// Returns true only when the declaration spells a non-optional function type
/// directly. Identifier/member types may be aliases and require the explicit
/// `escaping: true` contract instead.
internal func isDirectNonOptionalFunctionType(_ type: TypeSyntax) -> Bool {
    if type.is(FunctionTypeSyntax.self) {
        return true
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isDirectNonOptionalFunctionType(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return isDirectNonOptionalFunctionType(first.type)
    }

    return false
}

/// Returns true for optional spellings that are visible without resolving a
/// typealias. `escaping: true` is applied as a parameter type attribute, so an
/// explicit `Optional<Handler>` must be rejected just like `Handler?` instead
/// of leaking Swift errors from every generated initializer and override API.
internal func isExplicitOptionalType(_ type: TypeSyntax) -> Bool {
    if type.is(OptionalTypeSyntax.self)
        || type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return true
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isExplicitOptionalType(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return isExplicitOptionalType(first.type)
    }

    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == "Optional"
            && identifier.genericArgumentClause != nil
    }

    if let member = type.as(MemberTypeSyntax.self) {
        return member.baseType.as(IdentifierTypeSyntax.self)?.name.text == "Swift"
            && member.name.text == "Optional"
            && member.genericArgumentClause != nil
    }

    return false
}

/// The macro can prove a direct function type and can conservatively accept
/// identifier/member types that may resolve to a function typealias. Other
/// top-level shapes (notably optionals and collections) cannot accept
/// `@escaping` as a parameter type attribute.
internal func supportsExplicitEscapingInput(_ type: TypeSyntax) -> Bool {
    guard !isExplicitOptionalType(type) else {
        return false
    }

    if isDirectNonOptionalFunctionType(type) {
        return true
    }

    if type.is(IdentifierTypeSyntax.self) || type.is(MemberTypeSyntax.self) {
        return true
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return supportsExplicitEscapingInput(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return supportsExplicitEscapingInput(first.type)
    }

    return false
}

private func normalizedProviderType(_ type: TypeSyntax) -> TypeSyntax {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return normalizedProviderType(optional.wrappedType)
    }

    if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return normalizedProviderType(implicitlyUnwrapped.wrappedType)
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedProviderType(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return normalizedProviderType(first.type)
    }

    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == "Optional",
       let wrapped = identifier.genericArgumentClause?.arguments.first?.argument,
       let wrappedType = wrapped.as(TypeSyntax.self) {
        return normalizedProviderType(wrappedType)
    }

    return type
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
