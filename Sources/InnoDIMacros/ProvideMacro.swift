//
//  ProvideMacro.swift
//  InnoDIMacros
//

import SwiftSyntax
import SwiftSyntaxMacros

public struct ProvideMacro: PeerMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingPeersOf decl: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
