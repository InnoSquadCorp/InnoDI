import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private let assistedFactoryPrototypeTypeName = "_InnoDIAssistedFactoryPrototype"

/// Internal 5.2.x runway for validating the child-owned assisted-factory
/// semantics from RFC 0006. The public spelling and generated names remain
/// intentionally underscored and SPI-only until the RFC is accepted.
public struct InnoDIAssistedFactoryPrototypeMacro: MemberMacro {
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
        guard let container = declaration.as(StructDeclSyntax.self),
              findInnoDIAttribute(
                  named: "DIContainer",
                  in: declaration.attributes
              ) != nil else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: AssistedFactoryPrototypeDiagnostic(
                        "The assisted-factory prototype must be stacked on a struct annotated with @DIContainer.",
                        id: "requires-container"
                    )
                )
            )
            return []
        }

        guard let assistedNames = parseAssistedNames(
            from: attribute,
            in: context
        ) else {
            return []
        }

        let validationContext = DiagnosticSuppressingMacroExpansionContext(
            forwardingTo: context
        )
        guard classifyDIContainerDeclaration(
            declaration,
            lexicalContext: context.lexicalContext
        ).isSupported,
              DIContainerParser.userDefinedInitializers(in: declaration).isEmpty,
              let model = DIContainerParser.parse(
                  declaration: declaration,
                  context: validationContext
              ),
              DIContainerValidator.validate(
                  model: model,
                  declaration: declaration,
                  context: validationContext
              ) else {
            // The stable @DIContainer role owns diagnostics for an invalid
            // container. Do not duplicate them from this experimental role.
            return []
        }

        let inputNames = Set(model.inputMembers.map(\.name))
        let unknownNames = assistedNames.filter { !inputNames.contains($0) }
        guard unknownNames.isEmpty else {
            for name in unknownNames {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(attribute),
                        message: AssistedFactoryPrototypeDiagnostic(
                            "Assisted input '\(name)' must name a direct @Provide(.input) member on this container.",
                            id: "unknown-assisted-input"
                        )
                    )
                )
            }
            return []
        }

        guard !hasDirectTypeDeclaration(
            named: assistedFactoryPrototypeTypeName,
            in: declaration
        ) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: AssistedFactoryPrototypeDiagnostic(
                        "The container already declares '\(assistedFactoryPrototypeTypeName)', which is reserved by the assisted-factory prototype.",
                        id: "generated-name-conflict"
                    )
                )
            )
            return []
        }

        return [
            makeAssistedFactoryPrototypeDecl(
                container: container,
                model: model,
                assistedNames: Set(assistedNames)
            )
        ]
    }
}

private func parseAssistedNames(
    from attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> [String]? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          arguments.count == 1,
          let argument = arguments.first,
          argument.label?.text == "assisted",
          let array = argument.expression.as(ArrayExprSyntax.self) else {
        context.diagnose(
            Diagnostic(
                node: Syntax(attribute),
                message: AssistedFactoryPrototypeDiagnostic(
                    "The assisted-factory prototype requires assisted: with one literal array of direct input member names.",
                    id: "invalid-assisted-inputs"
                )
            )
        )
        return nil
    }

    var names: [String] = []
    for element in array.elements {
        guard let name = stringLiteralValue(element.expression) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(element.expression),
                    message: AssistedFactoryPrototypeDiagnostic(
                        "Each assisted input must be a plain string literal naming one direct input member.",
                        id: "invalid-assisted-inputs"
                    )
                )
            )
            return nil
        }
        names.append(name)
    }

    guard !names.isEmpty else {
        context.diagnose(
            Diagnostic(
                node: Syntax(attribute),
                message: AssistedFactoryPrototypeDiagnostic(
                    "The assisted-factory prototype requires at least one assisted input.",
                    id: "empty-assisted-inputs"
                )
            )
        )
        return nil
    }

    var seen: Set<String> = []
    guard names.allSatisfy({ seen.insert($0).inserted }) else {
        context.diagnose(
            Diagnostic(
                node: Syntax(attribute),
                message: AssistedFactoryPrototypeDiagnostic(
                    "Each assisted input may appear only once.",
                    id: "duplicate-assisted-input"
                )
            )
        )
        return nil
    }

    return names
}

private func makeAssistedFactoryPrototypeDecl(
    container: StructDeclSyntax,
    model: DIContainerExpansionModel,
    assistedNames: Set<String>
) -> DeclSyntax {
    let containerName = container.name.text
    let staticInputs = model.inputMembers.filter {
        !assistedNames.contains($0.name)
    }
    let assistedInputs = model.inputMembers.filter {
        assistedNames.contains($0.name)
    }
    let accessPrefix = model.accessLevel.map { "\($0) " } ?? ""
    let isolationPrefix = model.options.mainActor
        ? "@_Concurrency.MainActor\n"
        : ""

    let storedProperties = staticInputs.map { member in
        "private let \(member.name): \(member.type.trimmedDescription)"
    }.joined(separator: "\n")
    let factoryParameters = staticInputs.map { member in
        "\(member.name): \(inputParameterType(for: member).trimmedDescription)"
    }.joined(separator: ", ")
    let factoryAssignments = staticInputs.map { member in
        "self.\(member.name) = \(member.name)"
    }.joined(separator: "\n")

    let callParameters = assistedInputs.map { member in
        "\(member.name): \(inputParameterType(for: member).trimmedDescription)"
    } + [
        "_ _innoDIApplyOverrides: \(model.options.mainActor ? "@_Concurrency.MainActor " : "")(inout \(containerName).Overrides) -> Void = { _ in }",
    ]
    let forwardedInputs = model.inputMembers.map { member in
        let value = assistedNames.contains(member.name)
            ? member.name
            : "self.\(member.name)"
        return "\(member.name): \(value)"
    } + ["_innoDIApplyOverrides"]

    let bodySections = [
        storedProperties,
        """
        \(accessPrefix)init(\(factoryParameters)) {
            \(factoryAssignments)
        }
        """,
        """
        \(accessPrefix)func callAsFunction(
            \(callParameters.joined(separator: ",\n    "))
        ) -> \(containerName) {
            \(containerName)(
                \(forwardedInputs.joined(separator: ",\n        "))
            )
        }
        """,
    ].filter { !$0.isEmpty }.joined(separator: "\n\n")

    let declaration: DeclSyntax = """
    \(raw: isolationPrefix)\(raw: accessPrefix)struct \(raw: assistedFactoryPrototypeTypeName) {
        \(raw: bodySections)
    }
    """
    return declaration.prependingMARK(
        "// MARK: - Experimental Assisted Factory Prototype"
    )
}

private func hasDirectTypeDeclaration(
    named name: String,
    in declaration: some DeclGroupSyntax
) -> Bool {
    declaration.memberBlock.members.contains { member in
        let syntax = member.decl
        return syntax.as(StructDeclSyntax.self)?.name.text == name
            || syntax.as(ClassDeclSyntax.self)?.name.text == name
            || syntax.as(EnumDeclSyntax.self)?.name.text == name
            || syntax.as(ActorDeclSyntax.self)?.name.text == name
            || syntax.as(ProtocolDeclSyntax.self)?.name.text == name
            || syntax.as(TypeAliasDeclSyntax.self)?.name.text == name
    }
}

private struct AssistedFactoryPrototypeDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity = .error

    init(_ message: String, id: String) {
        self.message = message
        diagnosticID = MessageID(
            domain: "InnoDI.experimental",
            id: "assisted-factory-prototype.\(id)"
        )
    }
}
