//
//  ProvideMacro.swift
//  InnoDIMacros
//

import InnoDICore
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
        
        if parseResult.scope == .transient {
            let name = identifier.identifier.text
            let overrideName = "_override_\(name)"
            let decl: DeclSyntax = "private let \(raw: overrideName): \(type)?"
            return [decl]
        }
        
        return []
    }
    
    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        let parseResult = parseProvideArguments(attribute)
        
        guard parseResult.scope == ProvideScope.transient else {
            return []
        }
        
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return []
        }

        let name = identifier.identifier.text
        let overrideName = "_override_\(name)"
        
        let overrideCheck = CodeBlockItemSyntax(item: .stmt(StmtSyntax(
            """
            if let override = \(raw: overrideName) { return override }
            """
        )))

        var createExpr: ExprSyntax
        
        if let factory = parseResult.factoryExpr {
            if factory.is(ClosureExprSyntax.self) {
                 createExpr = ExprSyntax(FunctionCallExprSyntax(
                    calledExpression: factory,
                    leftParen: .leftParenToken(),
                    arguments: [],
                    rightParen: .rightParenToken()
                ))
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
                        base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
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
        } else {
            // If neither factory nor type provided, return empty (will cause compile error elsewhere or runtime crash if used)
            // Ideally we diagnose this in DIContainerMacro
            return []
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
    }
}
