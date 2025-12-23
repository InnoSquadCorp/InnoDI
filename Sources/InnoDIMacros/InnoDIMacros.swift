//
//  InnoDIMacros.swift
//  InnoDIMacros
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct InnoDIPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DIContainerMacro.self,
        ProvideMacro.self
    ]
}
