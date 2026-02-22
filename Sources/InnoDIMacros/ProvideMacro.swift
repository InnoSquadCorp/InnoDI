//
//  ProvideMacro.swift
//  InnoDIMacros
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct ProvideMacro: PeerMacro, AccessorMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = decl.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let type = binding.typeAnnotation?.type else {
            return []
        }
        
        let parseResult = parseProvideArguments(attribute)
        let name = identifier.identifier.text
        
        switch parseResult.scope {
        case .transient:
            let overrideName = "_override_\(name)"
            let decl: DeclSyntax = "private let \(raw: overrideName): \(type)?"
            return [decl]
        case .shared, .input:
            let storageName = "_storage_\(name)"
            let decl: DeclSyntax = "private let \(raw: storageName): \(type)"
            return [decl]
        case .none:
            return []
        }
    }
    
    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let parseResult = parseProvideArguments(attribute)
        
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return []
        }

        let name = identifier.identifier.text
        
        switch parseResult.scope {
        case .shared, .input:
            let storageName = "_storage_\(name)"
            let getter = AccessorDeclSyntax(
                accessorSpecifier: .keyword(.get),
                body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(raw: storageName)")))
                ]))
            )
            return [getter]
            
        case .transient:
            let overrideName = "_override_\(name)"
            
            let overrideCheck = CodeBlockItemSyntax(item: .stmt(StmtSyntax(
                """
                if let override = \(raw: overrideName) { return override }
                """
            )))

            var createExpr: ExprSyntax
            
            if let factory = parseResult.factoryExpr {
                if let closure = factory.as(ClosureExprSyntax.self) {
                    let parsedArguments = closureArgumentNames(closure: closure)
                    if parsedArguments.hasWildcard {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(closure),
                                message: SimpleDiagnostic("Transient factory closure parameters must be named for injection.")
                            )
                        )
                        return [fatalErrorGetter("Transient factory closure parameters must be named for injection.")]
                    }
                    createExpr = callClosureExpr(closure: closure, argumentNames: parsedArguments.names)
                } else {
                    createExpr = factory
                }
            } else if let typeExpr = parseResult.typeExpr {
                var args: [LabeledExprSyntax] = []
                for dep in parseResult.dependencies {
                    args.append(LabeledExprSyntax(
                        label: .identifier(dep),
                        colon: .colonToken(),
                        expression: ExprSyntax(MemberAccessExprSyntax(
                            base: DeclReferenceExprSyntax(baseName: .identifier("self")),
                            declName: DeclReferenceExprSyntax(baseName: .identifier(dep))
                        ))
                    ))
                }

                createExpr = ExprSyntax(FunctionCallExprSyntax(
                    calledExpression: typeExpr,
                    leftParen: .leftParenToken(),
                    arguments: LabeledExprListSyntax(args),
                    rightParen: .rightParenToken()
                ))
            } else if let initializer = binding.initializer?.value {
                createExpr = initializer
            } else {
                return [fatalErrorGetter("Missing factory for transient dependency")]
            }
            
            let getterBody = CodeBlockItemListSyntax([
                overrideCheck,
                CodeBlockItemSyntax(item: .stmt(StmtSyntax("return \(createExpr)")))
            ])
            
            let getter = AccessorDeclSyntax(
                accessorSpecifier: .keyword(.get),
                body: CodeBlockSyntax(statements: getterBody)
            )
            
            return [getter]
            
        case .none:
            let getter = AccessorDeclSyntax(
                accessorSpecifier: .keyword(.get),
                body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
                    CodeBlockItemSyntax(item: .stmt(StmtSyntax("fatalError(\"Unknown scope\")")))
                ]))
            )
            return [getter]
        }
    }
}

private struct ClosureArgumentList {
    let names: [String]
    let hasWildcard: Bool
}

private func closureArgumentNames(closure: ClosureExprSyntax) -> ClosureArgumentList {
    guard let signature = closure.signature,
          let parameterClause = signature.parameterClause else {
        return ClosureArgumentList(names: [], hasWildcard: false)
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

    return ClosureArgumentList(names: names, hasWildcard: hasWildcard)
}

private func callClosureExpr(closure: ClosureExprSyntax, argumentNames: [String]) -> ExprSyntax {
    var arguments: [LabeledExprSyntax] = []
    for (index, name) in argumentNames.enumerated() {
        let isLast = index == argumentNames.count - 1
        let argument = LabeledExprSyntax(
            label: nil,
            colon: nil,
            expression: ExprSyntax(MemberAccessExprSyntax(
                base: DeclReferenceExprSyntax(baseName: .identifier("self")),
                declName: DeclReferenceExprSyntax(baseName: .identifier(name))
            )),
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

private func fatalErrorGetter(_ message: String) -> AccessorDeclSyntax {
    let fatalErrorCall = FunctionCallExprSyntax(
        calledExpression: DeclReferenceExprSyntax(baseName: .identifier("fatalError")),
        leftParen: .leftParenToken(),
        arguments: LabeledExprListSyntax([
            LabeledExprSyntax(
                expression: ExprSyntax(StringLiteralExprSyntax(content: message))
            )
        ]),
        rightParen: .rightParenToken()
    )

    return AccessorDeclSyntax(
        accessorSpecifier: .keyword(.get),
        body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(ExprSyntax(fatalErrorCall)))
        ]))
    )
}
