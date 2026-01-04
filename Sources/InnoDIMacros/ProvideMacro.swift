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
                let getter = AccessorDeclSyntax(
                    accessorSpecifier: .keyword(.get),
                    body: CodeBlockSyntax(statements: CodeBlockItemListSyntax([
                        CodeBlockItemSyntax(item: .stmt(StmtSyntax("fatalError(\"Missing factory for transient dependency\")")))
                    ]))
                )
                return [getter]
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
