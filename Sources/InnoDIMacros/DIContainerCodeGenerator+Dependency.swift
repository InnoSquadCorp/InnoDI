//
//  DIContainerCodeGenerator+Dependency.swift
//  InnoDIMacros
//
//  Closure-parameter / dependency-name resolution helpers used by the
//  primary init and the factory-expression builder. These translate a
//  referenced dependency (by name or by closure parameter) into the
//  expression that should appear in the synthesized init — either
//  `self.<storage>`, a previously resolved `let` binding, a `.value` read
//  on an async task, or the `_innoDITrap` fallback when
//  `validateDAG: false` opts out of full graph resolution.
//

import SwiftSyntax
import SwiftSyntaxBuilder

private let storagePrefix = "_storage_"
private let unresolvedDependencyTrapName = "_innoDITrap"

/// Builds one argument expression per closure parameter of `member.factory`.
/// Soft parameters that point at a known soft target are replaced with
/// `Lazy({ _innoDILazyCell_<name>.resolve() })`; all other parameters fall back to
/// `self._storage_<resolved>` via `resolveClosureParameter`.
internal func closureArgumentExpressions(
    member: ProvideMemberModel,
    closure: ClosureExprSyntax,
    availableNames: [String],
    availableExpressions: [String: ExprSyntax] = [:],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> [ExprSyntax] {
    let references = member.closureParameterReferences
    // Shorthand closures or attribute-level mismatches may cause the
    // reference list to be out-of-sync with the AST; fall back to a
    // name-only parse in that case.
    if references.isEmpty {
        let parsed = parseClosureParameterNames(closure)
        return try parsed.names.map { name in
            try resolvedInitDependencyExpression(
                name: name,
                availableNames: availableNames,
                availableExpressions: availableExpressions,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
        }
    }

    var expressions: [ExprSyntax] = []
    for ref in references {
        if ref.kind == .soft {
            guard let calleeDescription = ref.lazyWrapperCalleeDescription else {
                throw CodegenInvariantError(description: "Unsupported soft dependency '\(ref.name)' reached code generation.")
            }
            if deferredTargetNameSet.contains(ref.name) {
                expressions.append(
                    makeLazyCellWrapperExpr(
                        name: ref.name,
                        calleeDescription: calleeDescription
                    )
                )
            } else if allowUnresolvedDependencyFallback {
                expressions.append(
                    unresolvedDeferredWrapperExpr(name: ref.name)
                )
            } else {
                throw CodegenInvariantError(description: "Unsupported soft dependency '\(ref.name)' reached code generation.")
            }
            continue
        }
        if ref.kind == .provider {
            guard let calleeDescription = ref.providerWrapperCalleeDescription else {
                throw CodegenInvariantError(description: "Unsupported provider dependency '\(ref.name)' reached code generation.")
            }
            if deferredTargetNameSet.contains(ref.name) {
                expressions.append(
                    makeProviderCellWrapperExpr(
                        name: ref.name,
                        calleeDescription: calleeDescription
                    )
                )
            } else if allowUnresolvedDependencyFallback {
                expressions.append(
                    unresolvedDeferredWrapperExpr(name: ref.name)
                )
            } else {
                throw CodegenInvariantError(description: "Unsupported provider dependency '\(ref.name)' reached code generation.")
            }
            continue
        }
        expressions.append(
            try resolvedInitDependencyExpression(
                name: ref.name,
                availableNames: availableNames,
                availableExpressions: availableExpressions,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
        )
    }
    return expressions
}

/// Builds the expression for a dependency name referenced by an async
/// factory: previously resolved `let` binding, `<task>.value` read, or
/// the unresolved fallback when DAG validation is disabled.
internal func dependencyExpression(
    for dependencyName: String,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    if let resolvedName = resolvedValueBindings[dependencyName] {
        return ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(resolvedName)))
    }

    if let taskBinding = taskBindings[dependencyName] {
        // <taskBinding.name>.value
        let valueAccess = MemberAccessExprSyntax(
            base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier(taskBinding.name))),
            declName: DeclReferenceExprSyntax(baseName: .identifier("value"))
        )
        let awaited = ExprSyntax(AwaitExprSyntax(expression: ExprSyntax(valueAccess)))
        if taskBinding.isThrowing {
            return ExprSyntax(TryExprSyntax(expression: awaited))
        }
        return awaited
    }

    return try unresolvedInitDependencyFallbackExpression(
        name: dependencyName,
        fallbackOverrideNames: fallbackOverrideNames,
        allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
    )
}

/// Translates each closure parameter name into its resolved storage name.
/// Aborts when a parameter can't be resolved — validation should have
/// caught that earlier.
internal func closureArgumentNames(closure: ClosureExprSyntax, availableNames: [String]) throws -> [String] {
    let parsedArguments = parseClosureParameterNames(closure)
    var result: [String] = []

    for (index, name) in parsedArguments.names.enumerated() {
        guard let resolvedName = resolveClosureParameter(name: name, availableNames: availableNames) else {
            throw CodegenInvariantError(description: "Unresolved closure parameter '\(name)' reached code generation at index \(index).")
        }
        result.append(resolvedName)
    }

    return result
}

/// Attempts to match a closure parameter name against the init's available
/// storage names, allowing the `_storage_` prefix to be present on either
/// side.
private func resolveClosureParameter(name: String, availableNames: [String]) -> String? {
    if availableNames.contains(name) {
        return name
    }

    let nameWithoutPrefix = name.hasPrefix(storagePrefix) ? String(name.dropFirst(storagePrefix.count)) : name

    for availableName in availableNames {
        let availableWithoutPrefix = availableName.hasPrefix(storagePrefix)
            ? String(availableName.dropFirst(storagePrefix.count))
            : availableName
        if availableWithoutPrefix == nameWithoutPrefix {
            return availableName
        }
    }

    return nil
}

/// Resolves a dependency reference into either `self.<resolved>` or the
/// unresolved fallback expression.
internal func resolvedInitDependencyExpression(
    name: String,
    availableNames: [String],
    availableExpressions: [String: ExprSyntax] = [:],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    if let expression = availableExpressions[name] {
        return expression
    }
    if let resolvedName = resolveClosureParameter(name: name, availableNames: availableNames) {
        if resolvedName.hasPrefix(storagePrefix) {
            return makeProviderStorageReadExpr(name: resolvedName)
        }
        return makeSelfMemberAccessExpr(name: resolvedName)
    }

    return try unresolvedInitDependencyFallbackExpression(
        name: name,
        fallbackOverrideNames: fallbackOverrideNames,
        allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
    )
}

private func unresolvedInitDependencyFallbackExpression(
    name: String,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    guard allowUnresolvedDependencyFallback else {
        throw CodegenInvariantError(description: "Unresolved dependency '\(name)' reached code generation.")
    }

    let unresolved = unresolvedDependencyHelperExpr(name: name)
    if fallbackOverrideNames.contains(name) {
        return nilCoalescingExpr(optionalName: name, fallback: unresolved)
    }
    return unresolved
}

private func unresolvedDependencyHelperExpr(name: String) -> ExprSyntax {
    let call = FunctionCallExprSyntax(
        calledExpression: MemberAccessExprSyntax(
            base: DeclReferenceExprSyntax(baseName: .identifier("InnoDI")),
            declName: DeclReferenceExprSyntax(baseName: .identifier(unresolvedDependencyTrapName))
        ),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(
                    StringLiteralExprSyntax(
                        content: "InnoDI could not resolve dependency '\(name)' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring."
                    )
                )
            )
        ]),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}

/// Builds a contextual `Lazy<T>` / `Provider<T>` wrapper whose resolver uses
/// the same typed runtime trap as unresolved hard edges when DAG validation is
/// explicitly disabled. The surrounding factory parameter supplies the
/// concrete wrapper type, so no user-visible or shadowable type qualifier is
/// required here.
internal func unresolvedDeferredWrapperExpr(name: String) -> ExprSyntax {
    let resolver = ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(
                item: .expr(unresolvedDependencyHelperExpr(name: name))
            )
        ])
    )
    return ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: MemberAccessExprSyntax(
                period: .periodToken(),
                declName: DeclReferenceExprSyntax(baseName: .keyword(.`init`))
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(expression: ExprSyntax(resolver))
            ]),
            rightParen: .rightParenToken()
        )
    )
}
