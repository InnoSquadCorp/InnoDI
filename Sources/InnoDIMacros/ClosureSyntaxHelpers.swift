import InnoDICore
import SwiftSyntax

struct ClosureParameterList {
    let names: [String]
    let references: [ClosureParameterReference]
    let hasWildcard: Bool
}

func parseClosureParameterNames(_ closure: ClosureExprSyntax) -> ClosureParameterList {
    guard let signature = closure.signature,
          let parameterClause = signature.parameterClause else {
        return ClosureParameterList(names: [], references: [], hasWildcard: false)
    }

    var names: [String] = []
    var references: [ClosureParameterReference] = []
    var hasWildcard = false

    switch parameterClause {
    case .simpleInput(let shorthandParameters):
        for parameter in shorthandParameters {
            let name = parameter.name.text
            if name == "_" {
                hasWildcard = true
                continue
            }
            names.append(name)
            // Shorthand closures don't carry type annotations at the
            // parameter site — `type` stays nil. Without a type we cannot
            // detect `Lazy<T>`, so shorthand params always register as `.hard`
            // edges. Users who want soft semantics must use full parameter
            // clauses (`{ (x: Lazy<T>) in … }`).
            references.append(
                ClosureParameterReference(
                    name: name,
                    token: parameter.name,
                    type: nil,
                    kind: .hard
                )
            )
        }
    case .parameterClause(let parameters):
        for parameter in parameters.parameters {
            let token = parameter.secondName ?? parameter.firstName
            let name = token.text
            if name == "_" {
                hasWildcard = true
                continue
            }
            names.append(name)
            let kind: DependencyKind
            switch deferredDependencyWrapperKind(for: parameter.type) {
            case .lazy:
                kind = .soft
            case .provider:
                kind = .provider
            case .none:
                kind = .hard
            }
            references.append(
                ClosureParameterReference(
                    name: name,
                    token: token,
                    type: parameter.type,
                    kind: kind
                )
            )
        }
    }

    return ClosureParameterList(names: names, references: references, hasWildcard: hasWildcard)
}

/// Returns `true` when a closure-parameter type annotation is syntactically
/// `Lazy<T>` (or `<Qualifier>.Lazy<T>` — most commonly `InnoDI.Lazy<T>`).
///
/// Detection is intentionally textual because macros run before type
/// resolution: a `typealias MyLazy = Lazy` cannot be recognized and will be
/// treated as an ordinary hard edge. This mirrors the existing `any Protocol`
/// detection limits and is documented at the public `Lazy<T>` declaration.
func isLazyType(_ type: TypeSyntax?) -> Bool {
    deferredDependencyWrapperKind(for: type) == .lazy
}

func lazyWrapperCalleeDescriptionForType(_ type: TypeSyntax?) -> String? {
    deferredDependencyWrapperCalleeDescription(for: type, kind: .lazy)
}

/// Returns `true` when a closure-parameter type annotation is syntactically
/// `Provider<T>` (or `<Qualifier>.Provider<T>` — most commonly
/// `InnoDI.Provider<T>`).
///
/// Detection mirrors `isLazyType`: the macro cannot resolve typealiases, so a
/// `typealias MyProvider = Provider` would be treated as an ordinary hard
/// edge. Documented at the public `Provider<T>` declaration in `InnoDI.swift`.
func isProviderType(_ type: TypeSyntax?) -> Bool {
    deferredDependencyWrapperKind(for: type) == .provider
}

func providerWrapperCalleeDescriptionForType(_ type: TypeSyntax?) -> String? {
    deferredDependencyWrapperCalleeDescription(for: type, kind: .provider)
}

func makeSelfMemberAccessExpr(name: String, baseName: String = "self") -> ExprSyntax {
    let base = DeclReferenceExprSyntax(baseName: .identifier(baseName))
    let memberAccess = MemberAccessExprSyntax(
        base: ExprSyntax(base),
        declName: DeclReferenceExprSyntax(baseName: .identifier(name))
    )
    return ExprSyntax(memberAccess)
}

/// Reads one of `@Provide`'s default-initialized optional backing slots after
/// the generated initializer has populated it. Keeping this force unwrap in a
/// single builder prevents init-time wiring from accidentally passing `T?`
/// into a factory, lazy cell, or child-container initializer that expects `T`.
func makeProviderStorageReadExpr(name: String, baseName: String = "self") -> ExprSyntax {
    ExprSyntax(
        ForceUnwrapExprSyntax(
            expression: makeSelfMemberAccessExpr(name: name, baseName: baseName)
        )
    )
}

func makeClosureCallExpr(closure: ClosureExprSyntax, argumentNames: [String], baseName: String = "self") -> ExprSyntax {
    let expressions = argumentNames.map { makeSelfMemberAccessExpr(name: $0, baseName: baseName) }
    return makeClosureCallExpr(closure: closure, argumentExpressions: expressions)
}

func makeClosureCallExpr(closure: ClosureExprSyntax, argumentExpressions: [ExprSyntax]) -> ExprSyntax {
    var arguments: [LabeledExprSyntax] = []

    for (index, expression) in argumentExpressions.enumerated() {
        let isLast = index == argumentExpressions.count - 1
        let argument = LabeledExprSyntax(
            label: nil,
            colon: nil,
            expression: expression,
            trailingComma: isLast ? nil : .commaToken()
        )
        arguments.append(argument)
    }

    let call = FunctionCallExprSyntax(
        calledExpression: ExprSyntax(closure),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax(arguments),
        rightParen: .rightParenToken()
    )

    return ExprSyntax(call)
}
