import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

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
        let userDefinedInitializers = DIContainerParser.userDefinedInitializers(in: decl)
        if !userDefinedInitializers.isEmpty {
            for initializer in userDefinedInitializers {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(initializer),
                        message: SimpleDiagnostic.containerCustomInitUnsupported(),
                        notes: [
                            Note(
                                node: Syntax(attribute),
                                message: SimpleNote(
                                    "The synthesized container initializer already covers .input members and optional dependency overrides.",
                                    code: .containerCustomInitUnsupported,
                                    suffix: "synthesized-init"
                                )
                            ),
                            Note(
                                node: Syntax(initializer),
                                message: SimpleNote(
                                    "Remove this custom initializer, or remove @DIContainer and wire the container manually.",
                                    code: .containerCustomInitUnsupported,
                                    suffix: "manual-wiring"
                                )
                            )
                        ]
                    )
                )
            }
            return []
        }

        guard let model = DIContainerParser.parse(declaration: decl, context: context) else {
            return []
        }

        if model.members.isEmpty && model.subContainerMembers.isEmpty {
            return []
        }

        let isValid = DIContainerValidator.validate(model: model, context: context)
        if !isValid {
            return []
        }

        do {
            if let conflict = DIContainerParser.findOverridesNameConflict(in: decl) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(conflict.node),
                        message: SimpleDiagnostic.containerOverridesNameConflict(kind: conflict.kind)
                    )
                )
                return [try DIContainerCodeGenerator.generateInit(for: model)]
            }

            return try DIContainerCodeGenerator.generateAll(for: model)
        } catch let error as CodegenInvariantError {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.internalCodegenInvariant(description: error.description)
                )
            )
            return []
        }
    }
}
