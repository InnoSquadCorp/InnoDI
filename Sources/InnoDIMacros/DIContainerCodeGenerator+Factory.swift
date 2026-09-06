//
//  DIContainerCodeGenerator+Factory.swift
//  InnoDIMacros
//
//  Expression builders that render a `@Provide` member's factory — raw
//  closure invocation, initializer call, or type-name call — into the
//  syntax tree emitted by the primary init. Handles sync and async
//  factories plus soft/provider parameter substitution.
//

import SwiftSyntax
import SwiftSyntaxBuilder

internal func makeFactoryExpr(
    member: ProvideMemberModel,
    availableNames: [String],
    availableExpressions: [String: ExprSyntax] = [:],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let argumentExpressions = try closureArgumentExpressions(
                member: member,
                closure: closure,
                availableNames: availableNames,
                availableExpressions: availableExpressions,
                deferredTargetNameSet: deferredTargetNameSet,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
            return makeClosureCallExpr(closure: closure, argumentExpressions: argumentExpressions)
        }
        return factory
    }

    if let initializer = member.initializer {
        return initializer
    }

    if let typeExpr = member.typeExpr {
        let args = try labeledDependencyArguments(
            dependencies: member.withDependencies,
            labels: member.withDependencyLabels,
            availableNames: availableNames,
            availableExpressions: availableExpressions,
            fallbackOverrideNames: fallbackOverrideNames,
            allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
        )

        let call = FunctionCallExprSyntax(
            calledExpression: typeExpr,
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax(args),
            rightParen: .rightParenToken()
        )
        return ExprSyntax(call)
    }

    throw CodegenInvariantError(description: "No factory expression available for member '\(member.name)' — validation should have caught this.")
}

/// Builds the synchronous factory expression stored by a deferred transient
/// target without capturing the enclosing container. Stable dependencies are
/// supplied as init-local values/cells, while hard transient dependencies are
/// expanded recursively. Lazy/Provider edges continue to resolve through the
/// init-local deferred cells, preserving re-entry and override behavior.
internal func makeDetachedTransientFactoryExpr(
    member: ProvideMemberModel,
    transientMembersByName: [String: ProvideMemberModel],
    stableExpressions: [String: ExprSyntax],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    try makeDetachedTransientFactoryExpr(
        member: member,
        transientMembersByName: transientMembersByName,
        stableExpressions: stableExpressions,
        deferredTargetNameSet: deferredTargetNameSet,
        fallbackOverrideNames: fallbackOverrideNames,
        allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback,
        expansionStack: []
    )
}

private func makeDetachedTransientFactoryExpr(
    member: ProvideMemberModel,
    transientMembersByName: [String: ProvideMemberModel],
    stableExpressions: [String: ExprSyntax],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool,
    expansionStack: Set<String>
) throws -> ExprSyntax {
    guard member.scope == .transient, !member.isAsyncFactory else {
        throw CodegenInvariantError(
            description: "Detached resolver requested for non-synchronous transient member '\(member.name)'."
        )
    }
    guard !expansionStack.contains(member.name) else {
        throw CodegenInvariantError(
            description: "Hard transient dependency cycle involving '\(member.name)' reached code generation."
        )
    }

    let nextStack = expansionStack.union([member.name])

    func hardDependencyExpression(_ name: String) throws -> ExprSyntax {
        if let stable = stableExpressions[name] {
            return stable
        }
        if let transient = transientMembersByName[name], !transient.isAsyncFactory {
            return try makeDetachedTransientFactoryExpr(
                member: transient,
                transientMembersByName: transientMembersByName,
                stableExpressions: stableExpressions,
                deferredTargetNameSet: deferredTargetNameSet,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback,
                expansionStack: nextStack
            )
        }
        return try resolvedInitDependencyExpression(
            name: name,
            availableNames: [],
            availableExpressions: stableExpressions,
            fallbackOverrideNames: fallbackOverrideNames,
            allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
        )
    }

    func dependencyExpression(_ reference: ClosureParameterReference) throws -> ExprSyntax {
        switch reference.kind {
        case .hard:
            return try hardDependencyExpression(reference.name)
        case .soft:
            guard deferredTargetNameSet.contains(reference.name),
                  let callee = reference.lazyWrapperCalleeDescription else {
                if allowUnresolvedDependencyFallback {
                    return unresolvedDeferredWrapperExpr(name: reference.name)
                }
                throw CodegenInvariantError(
                    description: "Unsupported soft dependency '\(reference.name)' reached detached transient code generation."
                )
            }
            return makeLazyCellWrapperExpr(
                name: reference.name,
                calleeDescription: callee
            )
        case .provider:
            guard deferredTargetNameSet.contains(reference.name),
                  let callee = reference.providerWrapperCalleeDescription else {
                if allowUnresolvedDependencyFallback {
                    return unresolvedDeferredWrapperExpr(name: reference.name)
                }
                throw CodegenInvariantError(
                    description: "Unsupported provider dependency '\(reference.name)' reached detached transient code generation."
                )
            }
            return makeProviderCellWrapperExpr(
                name: reference.name,
                calleeDescription: callee
            )
        }
    }

    let factoryExpression: ExprSyntax
    if member.isMultibinding {
        let elements = try member.withDependencies.map(hardDependencyExpression)
        factoryExpression = ExprSyntax(
            ArrayExprSyntax(
                leftSquare: .leftSquareToken(),
                elements: ArrayElementListSyntax(
                    elements.enumerated().map { index, expression in
                        ArrayElementSyntax(
                            expression: expression,
                            trailingComma: index == elements.count - 1 ? nil : .commaToken()
                        )
                    }
                ),
                rightSquare: .rightSquareToken()
            )
        )
    } else if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let expressions: [ExprSyntax]
            if member.closureParameterReferences.isEmpty {
                expressions = try member.closureDependencies.map(hardDependencyExpression)
            } else {
                expressions = try member.closureParameterReferences.map(dependencyExpression)
            }
            factoryExpression = makeClosureCallExpr(
                closure: closure,
                argumentExpressions: expressions
            )
        } else {
            factoryExpression = factory
        }
    } else if let initializer = member.initializer {
        factoryExpression = initializer
    } else if let typeExpression = member.typeExpr {
        guard member.withDependencies.count == member.withDependencyLabels.count else {
            throw CodegenInvariantError(
                description: "Initializer dependency labels do not match dependency values for '\(member.name)'."
            )
        }
        let arguments = try zip(
            member.withDependencyLabels,
            member.withDependencies
        ).enumerated().map { index, pair in
            LabeledExprSyntax(
                label: .identifier(pair.0),
                colon: .colonToken(),
                expression: try hardDependencyExpression(pair.1),
                trailingComma: index == member.withDependencies.count - 1
                    ? nil
                    : .commaToken()
            )
        }
        factoryExpression = ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: typeExpression,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax(arguments),
                rightParen: .rightParenToken()
            )
        )
    } else {
        throw CodegenInvariantError(
            description: "No detached factory expression available for transient member '\(member.name)'."
        )
    }

    return nilCoalescingExpr(
        optionalName: member.name,
        fallback: factoryExpression
    )
}

private func labeledDependencyArguments(
    dependencies: [String],
    labels: [String],
    availableNames: [String],
    availableExpressions: [String: ExprSyntax],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> [LabeledExprSyntax] {
    guard dependencies.count == labels.count else {
        throw CodegenInvariantError(
            description: "Initializer dependency labels do not match dependency values."
        )
    }
    return try zip(labels, dependencies).enumerated().map {
        index, pair in
        let (label, dependency) = pair
        return LabeledExprSyntax(
            label: .identifier(label),
            colon: .colonToken(),
            expression: try resolvedInitDependencyExpression(
                name: dependency,
                availableNames: availableNames,
                availableExpressions: availableExpressions,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            ),
            trailingComma: index == dependencies.count - 1 ? nil : .commaToken()
        )
    }
}

internal func makeAsyncFactoryExpr(
    member: ProvideMemberModel,
    resolvedValueBindings: [String: String],
    taskBindings: [String: AsyncTaskBinding],
    deferredTargetNameSet: Set<String>,
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> ExprSyntax {
    // If codegen was asked to build the task body without an async factory,
    // that is a validator bug — throw so the top-level macro emits a
    // diagnostic instead of silently generating invalid source.
    guard let asyncFactory = member.asyncFactory else {
        throw CodegenInvariantError(description: "Missing async factory for shared dependency '\(member.name)'.")
    }

    if let closure = asyncFactory.as(ClosureExprSyntax.self) {
        let references = member.closureParameterReferences
        let expressions: [ExprSyntax] = try references.map { ref in
            if ref.kind == .soft {
                guard let calleeDescription = ref.lazyWrapperCalleeDescription else {
                    throw CodegenInvariantError(description: "Unsupported soft dependency '\(ref.name)' reached async code generation.")
                }
                if deferredTargetNameSet.contains(ref.name) {
                    return makeLazyCellWrapperExpr(
                        name: ref.name,
                        calleeDescription: calleeDescription
                    )
                }
                if allowUnresolvedDependencyFallback {
                    return unresolvedDeferredWrapperExpr(name: ref.name)
                }
                throw CodegenInvariantError(description: "Unsupported soft dependency '\(ref.name)' reached async code generation.")
            }
            if ref.kind == .provider {
                guard let calleeDescription = ref.providerWrapperCalleeDescription else {
                    throw CodegenInvariantError(description: "Unsupported provider dependency '\(ref.name)' reached async code generation.")
                }
                if deferredTargetNameSet.contains(ref.name) {
                    return makeProviderCellWrapperExpr(
                        name: ref.name,
                        calleeDescription: calleeDescription
                    )
                }
                if allowUnresolvedDependencyFallback {
                    return unresolvedDeferredWrapperExpr(name: ref.name)
                }
                throw CodegenInvariantError(description: "Unsupported provider dependency '\(ref.name)' reached async code generation.")
            }
            return try dependencyExpression(
                for: ref.name,
                resolvedValueBindings: resolvedValueBindings,
                taskBindings: taskBindings,
                fallbackOverrideNames: fallbackOverrideNames,
                allowUnresolvedDependencyFallback: allowUnresolvedDependencyFallback
            )
        }
        return makeClosureCallExpr(closure: closure, argumentExpressions: expressions)
    }

    return asyncFactory
}
