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
            availableNames: availableNames,
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

private func labeledDependencyArguments(
    dependencies: [String],
    availableNames: [String],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) throws -> [LabeledExprSyntax] {
    try dependencies.enumerated().map { index, dependency in
        LabeledExprSyntax(
            label: .identifier(dependency),
            colon: .colonToken(),
            expression: try resolvedInitDependencyExpression(
                name: dependency,
                availableNames: availableNames,
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
