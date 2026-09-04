import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion roles used only by the required-role 6.0 container
/// overload. Keeping the legacy declaration on `DIContainerMacro` prevents
/// the compiler from applying extension-role structural restrictions to every
/// 5.x container before InnoDI can emit its established diagnostics.
public struct DIContainerRoleMacro: MemberMacro, MemberAttributeMacro, PeerMacro,
    ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try DIContainerMacro.expansion(
            of: node,
            providingMembersOf: declaration,
            conformingTo: protocols,
            in: context
        )
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        try DIContainerMacro.expansion(
            of: node,
            attachedTo: declaration,
            providingAttributesFor: member,
            in: context
        )
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let group = declaration.as(StructDeclSyntax.self),
              parseDIContainerAttribute(group.attributes)?.role == .component,
              !hasHierarchyAttribute(named: "DIComponent", in: group.attributes) else {
            return []
        }
        return try DIComponentMacro.expansion(
            of: node,
            providingPeersOf: declaration,
            in: context
        )
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let options = parseDIContainerAttribute(declaration.attributes) else {
            return []
        }
        if options.role == .component {
            return try DIComponentMacro.expansion(
                of: node,
                attachedTo: declaration,
                providingExtensionsOf: type,
                conformingTo: protocols,
                in: context
            )
        }
        if options.role == .root {
            return try DIHierarchyRootMacro.expansion(
                of: node,
                attachedTo: declaration,
                providingExtensionsOf: type,
                conformingTo: protocols,
                in: context
            )
        }
        return []
    }
}
