import SwiftSyntax
import SwiftSyntaxMacros

public struct DIContainerMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: attribute, providingMembersOf: decl, in: context)
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if DIContainerParser.hasUserDefinedInit(in: decl) {
            return []
        }

        guard let model = DIContainerParser.parse(declaration: decl, context: context) else {
            return []
        }

        if model.members.isEmpty {
            return []
        }

        let isValid = DIContainerValidator.validate(model: model, context: context)
        if !isValid {
            return []
        }

        return [DIContainerCodeGenerator.generateInit(for: model)]
    }
}
