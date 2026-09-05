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

        // The outer @DIContainer member-attribute expansion has the complete
        // sibling source needed to preserve input declaration order and
        // escaping function contracts. It attaches the internal metadata
        // macro that owns member generation; this public macro owns only the
        // source-local declaration and argument diagnostics.
        return []
    }
}

struct AssistedFactoryArguments {
    let childType: ExprSyntax
    let staticInputs: [String]
    let assistedInputs: [String]
}

private struct AssistedFactoryInput {
    let name: String
    let requiresEscaping: Bool
}

func parseAssistedFactoryArguments(
    _ attribute: AttributeSyntax
) -> AssistedFactoryArguments? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self)
    else { return nil }
    var childType: ExprSyntax?
    var staticExpression: ExprSyntax?
    var assistedExpression: ExprSyntax?
    for argument in arguments {
        switch argument.label?.text {
        case "static":
            staticExpression = argument.expression
        case "assisted":
            assistedExpression = argument.expression
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
    guard let childType, let staticExpression, let assistedExpression,
          let staticInputs = parseChildKeyPathArray(
              staticExpression,
              childType: childType
          ),
          let assistedInputs = parseChildKeyPathArray(
              assistedExpression,
              childType: childType
          ) else { return nil }
    return AssistedFactoryArguments(
        childType: childType,
        staticInputs: staticInputs,
        assistedInputs: assistedInputs
    )
}

private func parseChildKeyPathArray(
    _ expression: ExprSyntax,
    childType: ExprSyntax
) -> [String]? {
    guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
    let expectedRoot = childType.trimmedDescription
    for element in array.elements {
        guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
              keyPath.root?.trimmedDescription == expectedRoot,
              keyPath.components.count == 1 else {
            return nil
        }
    }
    guard case let .parsed(names) = parseKeyPathArrayArgumentState(expression)
    else { return nil }
    return names
}

private struct AssistedFactoryMetadata {
    let inputs: [AssistedFactoryInput]
    let isMainActor: Bool
}

private func parseAssistedFactoryMetadata(
    _ attribute: AttributeSyntax
) -> AssistedFactoryMetadata? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let order = parseStringArrayArgument(named: "order", in: arguments),
          let escaping = parseStringArrayArgument(
              named: "escaping",
              in: arguments
          ),
          let mainActor = arguments.first(where: {
              $0.label?.text == "mainActor"
          })?.expression.trimmedDescription else { return nil }
    let escapingNames = Set(escaping)
    guard mainActor == "true" || mainActor == "false" else { return nil }
    return AssistedFactoryMetadata(
        inputs: order.map {
            AssistedFactoryInput(
                name: $0,
                requiresEscaping: escapingNames.contains($0)
            )
        },
        isMainActor: mainActor == "true"
    )
}

private func parseStringArrayArgument(
    named label: String,
    in arguments: LabeledExprListSyntax
) -> [String]? {
    guard let expression = arguments.first(where: {
        $0.label?.text == label
    })?.expression,
    let array = expression.as(ArrayExprSyntax.self) else { return nil }
    return array.elements.compactMap {
        stringLiteralValue($0.expression)
    }.count == array.elements.count
        ? array.elements.compactMap { stringLiteralValue($0.expression) }
        : nil
}

/// Carries source-order and escaping information from the outer container's
/// member-attribute expansion to its nested assisted-factory expansion.
public struct InnoDIAssistedFactoryMetadataMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let factory = declaration.as(StructDeclSyntax.self),
              let assistedFactoryAttribute = findInnoDIAttribute(
                  named: "AssistedFactory",
                  in: factory.attributes
              ),
              let arguments = parseAssistedFactoryArguments(
                  assistedFactoryAttribute
              ),
              let metadata = parseAssistedFactoryMetadata(node) else {
            return []
        }
        return makeAssistedFactoryMembers(
            factory: factory,
            arguments: arguments,
            childInputs: metadata.inputs,
            isMainActor: metadata.isMainActor
        )
    }
}

private func makeAssistedFactoryMembers(
    factory: StructDeclSyntax,
    arguments: AssistedFactoryArguments,
    childInputs: [AssistedFactoryInput],
    isMainActor: Bool
) -> [DeclSyntax] {
    let childType = arguments.childType.trimmedDescription
    let access = factory.modifiers.first { modifier in
        ["public", "package", "internal", "fileprivate", "private"]
            .contains(modifier.name.text)
    }?.name.text
    let accessPrefix = access.map { "\($0) " } ?? ""
    let isolationPrefix = isMainActor ? "@_Concurrency.MainActor " : ""
    let listedNames = arguments.staticInputs + arguments.assistedInputs
    guard Set(childInputs.map(\.name)) == Set(listedNames),
          childInputs.count == listedNames.count else { return [] }
    let canonicalInputs = childInputs
    let staticNames = Set(arguments.staticInputs)
    let assistedNames = Set(arguments.assistedInputs)
    let orderedStaticInputs = canonicalInputs.filter {
        staticNames.contains($0.name)
    }
    let orderedAssistedInputs = canonicalInputs.filter {
        assistedNames.contains($0.name)
    }

    func parameterType(for input: AssistedFactoryInput) -> String {
        let type = "\(childType)._InnoDIInputType_\(input.name)"
        return input.requiresEscaping ? "@escaping \(type)" : type
    }

    var declarations: [DeclSyntax] = orderedStaticInputs.map { input in
        DeclSyntax(
            "private let \(raw: input.name): \(raw: childType)._InnoDIInputType_\(raw: input.name)"
        )
    }

    let initParameters = orderedStaticInputs.map { input in
        "\(input.name): \(parameterType(for: input))"
    }.joined(separator: ", ")
    let assignments = orderedStaticInputs.map { input in
        "self.\(input.name) = \(input.name)"
    }.joined(separator: "\n")
    declarations.append(
        DeclSyntax(
            stringLiteral: "\(isolationPrefix)\(accessPrefix)init(\(initParameters)) {\n\(assignments)\n}"
        )
    )

    let callParameters = orderedAssistedInputs.map { input in
        "\(input.name): \(parameterType(for: input))"
    } + [
        "_ _innoDIApplyOverrides: \(overrideApplyClosureType(overridesTypeDescription: "\(childType).Overrides", isMainActor: isMainActor).trimmedDescription) = { _ in }",
    ]
    let forwardedInputs = canonicalInputs.map { input in
        if staticNames.contains(input.name) {
            return "\(input.name): self.\(input.name)"
        }
        return "\(input.name): \(input.name)"
    } + ["_innoDIApplyOverrides"]
    declarations.append(
        DeclSyntax(
            stringLiteral: """
            \(isolationPrefix)\(accessPrefix)func callAsFunction(
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
