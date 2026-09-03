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
        InnoDIAssistedFactoryPrototypeMacro.self,
        DIComponentMacro.self,
        DIHierarchyRootMacro.self,
        ProvideMacro.self,
        InnoDIProvideAccessorMacro.self,
        SubContainerMacro.self,
        InnoDISubContainerAccessorMacro.self,
        DIEnvironmentBridgeMacro.self,
        PreviewWithContainerMacro.self,
        GenerateMockMacro.self
    ]
}
