//
//  DIEnvironmentBridgeMacro.swift
//  InnoDIMacros
//
//  Macro entry points for SwiftUI environment bridge synthesis.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIEnvironmentBridgeMacro {}

let environmentBridgeModifierTypeName = "_InnoDIEnvironmentBridgeModifier"
let environmentBridgeHelperName = "_innoDIEnvironmentBridgeModifier"

extension DIEnvironmentBridgeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard isSupportedDIContainerDeclarationIfPresent(declaration, in: context) else {
            return []
        }

        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: true
        )
        guard let mappings = validation.mappings else {
            return []
        }

        guard let nominalType = nominalTypeSyntax(for: declaration) else {
            return []
        }

        let accessLevel = environmentBridgeAccessLevelModifiers(
            for: declaration.modifiers
        )
        let declarationSyntax = Syntax(declaration)
        let targetName = nominalDeclarationNameToken(
            in: declarationSyntax
        ).map(unescapedInnoDIIdentifierName)
        let targetLookupShadowsModifierType = targetName
            == environmentBridgeModifierTypeName
            || genericParameterNameTokens(in: declarationSyntax).contains {
                unescapedInnoDIIdentifierName($0)
                    == environmentBridgeModifierTypeName
            }
        let nestedTypeShadowsTarget = targetName.map { targetName in
            directContainerDeclarationNames(in: declaration).contains {
                $0.namespace == .type && $0.name == targetName
            }
        } ?? false
        let visibleGenericParameterNames =
            environmentBridgeVisibleGenericParameterNames(
                for: declaration,
                lexicalContext: context.lexicalContext
            )
        let visibleGenericShadowsTarget = targetName.map(
            visibleGenericParameterNames.contains
        ) ?? false
        let requiresShadowSafeStorage = targetLookupShadowsModifierType
            || nestedTypeShadowsTarget
            || visibleGenericShadowsTarget
        let shadowSafeTypeNames = makeEnvironmentBridgeShadowSafeTypeNames(
            mappingCount: mappings.count,
            excluding: visibleGenericParameterNames
        )
        let modifierDecl = requiresShadowSafeStorage
            ? makeShadowSafeEnvironmentBridgeModifierDecl(
                accessLevel: accessLevel,
                typeNames: shadowSafeTypeNames
            )
            : makeEnvironmentBridgeModifierDecl(
                accessLevel: accessLevel,
                containerType: nominalType,
                mappings: mappings
            )
        let bridgeMethodDecl = requiresShadowSafeStorage
            ? makeShadowSafeEnvironmentBridgeHelperDecl(
                accessLevel: accessLevel,
                mappings: mappings
            )
            : makeEnvironmentBridgeHelperDecl(accessLevel: accessLevel)

        return [DeclSyntax(modifierDecl), DeclSyntax(bridgeMethodDecl)]
    }
}

extension DIEnvironmentBridgeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard isSupportedDIContainerDeclarationIfPresent(declaration, in: context) else {
            return []
        }

        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: false
        )
        guard validation.mappings != nil else {
            return []
        }

        return [
            try ExtensionDeclSyntax(
                "extension \(type): InnoDISwiftUI.DIEnvironmentBridging {}"
            )
        ]
    }
}
