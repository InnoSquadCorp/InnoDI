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
        []
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
        
        guard let factory = parseResult.factoryExpr else {
            return []
        }
        
        let getterBody = CodeBlockItemListSyntax([
            CodeBlockItemSyntax(item: .expr(factory))
        ])
        
        let getter = AccessorDeclSyntax(
            accessorSpecifier: .keyword(.get),
            body: CodeBlockSyntax(statements: getterBody)
        )
        
        return [getter]
    }
}
