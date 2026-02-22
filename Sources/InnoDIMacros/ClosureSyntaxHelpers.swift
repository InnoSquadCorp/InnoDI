import SwiftSyntax

struct ClosureParameterList {
    let names: [String]
    let hasWildcard: Bool
}

func parseClosureParameterNames(_ closure: ClosureExprSyntax) -> ClosureParameterList {
    guard let signature = closure.signature,
          let parameterClause = signature.parameterClause else {
        return ClosureParameterList(names: [], hasWildcard: false)
    }

    var names: [String] = []
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
        }
    case .parameterClause(let parameters):
        for parameter in parameters.parameters {
            let name = parameter.secondName?.text ?? parameter.firstName.text
            if name == "_" {
                hasWildcard = true
                continue
            }
            names.append(name)
        }
    }

    return ClosureParameterList(names: names, hasWildcard: hasWildcard)
}

func makeSelfMemberAccessExpr(name: String, baseName: String = "self") -> ExprSyntax {
    let base = DeclReferenceExprSyntax(baseName: .identifier(baseName))
    let memberAccess = MemberAccessExprSyntax(
        base: ExprSyntax(base),
        declName: DeclReferenceExprSyntax(baseName: .identifier(name))
    )
    return ExprSyntax(memberAccess)
}

func makeClosureCallExpr(closure: ClosureExprSyntax, argumentNames: [String], baseName: String = "self") -> ExprSyntax {
    var arguments: [LabeledExprSyntax] = []

    for (index, name) in argumentNames.enumerated() {
        let isLast = index == argumentNames.count - 1
        let argument = LabeledExprSyntax(
            label: nil,
            colon: nil,
            expression: makeSelfMemberAccessExpr(name: name, baseName: baseName),
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
