import InnoDICore
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Supplies the implementation of a source-written nested `AssistedFactory`.
///
/// The attribute carries rename-safe child key paths rather than repeated
/// types. Each `@Input` peer provides a generated type alias that is visible in
/// this source file, so the emitted initializer and call signature remain
/// fully typed while the nominal factory itself remains visible target-wide.
public struct AssistedFactoryMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(
            of: attribute,
            providingMembersOf: declaration,
            in: context
        )
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let factory = declaration.as(StructDeclSyntax.self),
              factory.name.text == "AssistedFactory",
              factory.genericParameterClause == nil,
              factory.genericWhereClause == nil,
              factory.memberBlock.members.isEmpty else {
            context.emit(
                SimpleDiagnostic.assistedFactoryInvalidDeclaration(),
                at: Syntax(attribute)
            )
            return []
        }

        guard let arguments = parseAssistedFactoryArguments(attribute),
              !arguments.assistedInputs.isEmpty else {
            context.emit(
                SimpleDiagnostic.assistedFactoryInvalidArguments(),
                at: Syntax(attribute)
            )
            return []
        }

        let allNames = arguments.staticInputs + arguments.assistedInputs
        guard Set(allNames).count == allNames.count else {
            context.emit(
                SimpleDiagnostic.assistedFactoryDuplicateInput(),
                at: Syntax(attribute)
            )
            return []
        }

        return makeAssistedFactoryMembers(
            factory: factory,
            arguments: arguments
        )
    }
}

struct AssistedFactoryArguments {
    let childType: ExprSyntax
    let staticInputs: [String]
    let assistedInputs: [String]
}

func parseAssistedFactoryArguments(
    _ attribute: AttributeSyntax
) -> AssistedFactoryArguments? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self)
    else { return nil }
    var childType: ExprSyntax?
    var staticInputs: [String]?
    var assistedInputs: [String]?
    for argument in arguments {
        switch argument.label?.text {
        case "static":
            guard case let .parsed(names) =
                    parseKeyPathArrayArgumentState(argument.expression) else {
                return nil
            }
            staticInputs = names
        case "assisted":
            guard case let .parsed(names) =
                    parseKeyPathArrayArgumentState(argument.expression) else {
                return nil
            }
            assistedInputs = names
        case nil:
            guard let member = argument.expression.as(
                MemberAccessExprSyntax.self
            ), member.declName.baseName.text == "self",
               let base = member.base else {
                return nil
            }
            childType = base
        default:
            return nil
        }
    }
    guard let childType, let staticInputs, let assistedInputs else { return nil }
    return AssistedFactoryArguments(
        childType: childType,
        staticInputs: staticInputs,
        assistedInputs: assistedInputs
    )
}

private func makeAssistedFactoryMembers(
    factory: StructDeclSyntax,
    arguments: AssistedFactoryArguments
) -> [DeclSyntax] {
    let childType = arguments.childType.trimmedDescription
    let access = factory.modifiers.first { modifier in
        ["public", "package", "internal", "fileprivate", "private"]
            .contains(modifier.name.text)
    }?.name.text
    let accessPrefix = access.map { "\($0) " } ?? ""

    var declarations: [DeclSyntax] = arguments.staticInputs.map { name in
        DeclSyntax(
            "private let \(raw: name): \(raw: childType)._InnoDIInputType_\(raw: name)"
        )
    }

    let initParameters = arguments.staticInputs.map { name in
        "\(name): \(childType)._InnoDIInputType_\(name)"
    }.joined(separator: ", ")
    let assignments = arguments.staticInputs.map { name in
        "self.\(name) = \(name)"
    }.joined(separator: "\n")
    declarations.append(
        DeclSyntax(
            stringLiteral: "\(accessPrefix)init(\(initParameters)) {\n\(assignments)\n}"
        )
    )

    let callParameters = arguments.assistedInputs.map { name in
        "\(name): \(childType)._InnoDIInputType_\(name)"
    } + [
        "_ _innoDIApplyOverrides: (inout \(childType).Overrides) -> Void = { _ in }",
    ]
    let forwardedInputs = arguments.staticInputs.map { name in
        "\(name): self.\(name)"
    } + arguments.assistedInputs.map { name in
        "\(name): \(name)"
    } + ["_innoDIApplyOverrides"]
    declarations.append(
        DeclSyntax(
            stringLiteral: """
            \(accessPrefix)func callAsFunction(
                \(callParameters.joined(separator: ",\n    "))
            ) -> \(childType) {
                \(childType)(
                    \(forwardedInputs.joined(separator: ",\n        "))
                )
            }
            """
        )
    )
    return declarations
}
