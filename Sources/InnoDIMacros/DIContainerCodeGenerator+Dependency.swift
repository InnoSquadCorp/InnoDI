//
//  DIContainerCodeGenerator+Dependency.swift
//  InnoDIMacros
//
//  Closure-parameter / dependency-name resolution helpers used by the
//  primary init and the factory-expression builder. These translate a
//  referenced dependency (by name or by closure parameter) into the
//  expression that should appear in the synthesized init — either
//  `self.<storage>`, a previously resolved `let` binding, a `.value` read
//  on an async task, or the `_innoDIUnresolvedDependency` fallback when
//  `validateDAG: false` opts out of full graph resolution.
//

import SwiftSyntax
import SwiftSyntaxBuilder

private let unresolvedDependencyHelperName = "_innoDIUnresolvedDependency"

/// Builds one argument expression per closure parameter of `member.factory`.
/// Soft parameters that point at a known soft target are replaced with
/// `Lazy({ _lazyCell_<name>.value! })`; all other parameters fall back to
/// `self._storage_<resolved>` via `resolveClosureParameter`.
internal func closureArgumentExpressions(
    member: ProvideMemberModel,
    closure: ClosureExprSyntax,
    availableNames: [String],
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
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
        }
    }

    var expressions: [ExprSyntax] = []
    for ref in references {
        if ref.kind == .soft {
            guard deferredTargetNameSet.contains(ref.name),
                  let calleeDescription = ref.lazyWrapperCalleeDescription else {
                throw CodegenInvariantError(description: "Unsupported soft dependency '\(ref.name)' reached code generation.")
            }
            expressions.append(makeLazyCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription))
            continue
        }
        if ref.kind == .provider {
            guard deferredTargetNameSet.contains(ref.name),
                  let calleeDescription = ref.providerWrapperCalleeDescription else {
                throw CodegenInvariantError(description: "Unsupported provider dependency '\(ref.name)' reached code generation.")
            }
            expressions.append(makeProviderCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription))
            continue
        }
        expressions.append(
            try resolvedInitDependencyExpression(
                name: ref.name,
                availableNames: availableNames,
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

    let nameWithoutPrefix = name.hasPrefix("_storage_") ? String(name.dropFirst(9)) : name

    for availableName in availableNames {
        let availableWithoutPrefix = availableName.hasPrefix("_storage_") ? String(availableName.dropFirst(9)) : availableName
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
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    if let resolvedName = resolveClosureParameter(name: name, availableNames: availableNames) {
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

/// Emits the local `_innoDIUnresolvedDependency<T>(_: String) -> T` helper
/// that `validateDAG: false` containers call when a dependency can't be
/// located in the init's resolved bindings.
internal func unresolvedDependencyHelperDecl() -> DeclSyntax {
    DeclSyntax(
        """
        func \(raw: unresolvedDependencyHelperName)<T>(_ name: String) -> T {
            fatalError("InnoDI could not resolve dependency '\\(name)' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring.")
        }
        """
    )
}

private func unresolvedDependencyHelperExpr(name: String) -> ExprSyntax {
    let call = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier(unresolvedDependencyHelperName)),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(expression: ExprSyntax(StringLiteralExprSyntax(content: name)))
        ]),
        rightParen: .rightParenToken()
    )
    return ExprSyntax(call)
}
