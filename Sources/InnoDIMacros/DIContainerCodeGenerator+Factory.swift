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
) -> ExprSyntax {
    if let factory = member.factory {
        if let closure = factory.as(ClosureExprSyntax.self) {
            let argumentExpressions = closureArgumentExpressions(
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
        let args = labeledDependencyArguments(
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

    fatalError("No factory expression available - validation should have caught this")
}

private func labeledDependencyArguments(
    dependencies: [String],
    availableNames: [String],
    fallbackOverrideNames: Set<String>,
    allowUnresolvedDependencyFallback: Bool
) -> [LabeledExprSyntax] {
    dependencies.enumerated().map { index, dependency in
        LabeledExprSyntax(
            label: .identifier(dependency),
            colon: .colonToken(),
            expression: resolvedInitDependencyExpression(
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
) -> ExprSyntax {
    guard let asyncFactory = member.asyncFactory else {
        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(expression: ExprSyntax(StringLiteralExprSyntax(content: "Missing async factory for shared dependency '\(member.name)'.")))
                ]),
                rightParen: .rightParenToken()
            )
        )
    }

    if let closure = asyncFactory.as(ClosureExprSyntax.self) {
        let references = member.closureParameterReferences
        let expressions: [ExprSyntax] = references.map { ref in
            if ref.kind == .soft {
                guard deferredTargetNameSet.contains(ref.name),
                      let calleeDescription = ref.lazyWrapperCalleeDescription else {
                    fatalError("Unsupported soft dependency '\(ref.name)' reached async code generation.")
                }
                return makeLazyCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription)
            }
            if ref.kind == .provider {
                guard deferredTargetNameSet.contains(ref.name),
                      let calleeDescription = ref.providerWrapperCalleeDescription else {
                    fatalError("Unsupported provider dependency '\(ref.name)' reached async code generation.")
                }
                return makeProviderCellWrapperExpr(name: ref.name, calleeDescription: calleeDescription)
            }
            return dependencyExpression(
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
