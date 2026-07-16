//
//  DIContainerValidatorTypeChecks.swift
//  InnoDIMacros
//
//  Macro-module compatibility shims for the syntax-only generation gates that
//  now live in InnoDICore. Keeping callers on these short names avoids mixing
//  diagnostics with the shared build-preflight implementation.
//

import InnoDICore
import SwiftSyntax

internal func isOpaqueSomeType(_ type: TypeSyntax) -> Bool {
    InnoDICore.isOpaqueSomeType(type)
}

internal func isImplicitlyUnwrappedOptionalType(
    _ type: TypeSyntax
) -> Bool {
    InnoDICore.isImplicitlyUnwrappedOptionalType(type)
}

internal func isDirectNonOptionalFunctionType(
    _ type: TypeSyntax
) -> Bool {
    InnoDICore.isDirectNonOptionalFunctionType(type)
}

internal func supportsExplicitEscapingInput(_ type: TypeSyntax) -> Bool {
    InnoDICore.supportsExplicitEscapingInput(type)
}

internal func isAsyncClosureExpression(_ expression: ExprSyntax) -> Bool {
    InnoDICore.isAsyncClosureExpression(expression)
}

internal func isThrowingClosureExpression(_ expression: ExprSyntax) -> Bool {
    InnoDICore.isThrowingClosureExpression(expression)
}

internal func factoryExpressionContainsAwait(
    _ expression: ExprSyntax
) -> Bool {
    InnoDICore.factoryExpressionContainsAwait(expression)
}

internal func factoryExpressionContainsPlainTry(
    _ expression: ExprSyntax
) -> Bool {
    InnoDICore.factoryExpressionContainsPlainTry(expression)
}
