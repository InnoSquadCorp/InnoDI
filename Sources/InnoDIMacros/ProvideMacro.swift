//
//  ProvideMacro.swift
//  InnoDIMacros
//

import SwiftSyntax
import SwiftSyntaxMacros

public struct ProvideMacro: AccessorMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingAccessorsOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        []
    }
}
