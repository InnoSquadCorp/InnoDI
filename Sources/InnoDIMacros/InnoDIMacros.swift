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
        DIComponentMacro.self,
        DIHierarchyRootMacro.self,
        ProvideMacro.self,
        SubContainerMacro.self,
        DIEnvironmentBridgeMacro.self,
        DIFeatureRootMacro.self,
        PreviewWithContainerMacro.self
    ]
}
