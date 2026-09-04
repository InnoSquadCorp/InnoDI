import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private let multibindingPrototypeMemberName = "_innoDIMultibindingPrototype"

/// Internal 5.2.x runway for validating deterministic collection binding
/// semantics without freezing the RFC's 6.0 public spelling.
public struct InnoDIMultibindingPrototypeMacro: MemberMacro {
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
        guard declaration.is(StructDeclSyntax.self),
              findInnoDIAttribute(
                  named: "DIContainer",
                  in: declaration.attributes
              ) != nil else {
            diagnose(
                "The multibinding prototype must be stacked on a struct annotated with @DIContainer.",
                id: "requires-container",
                at: Syntax(attribute),
                in: context
            )
            return []
        }

        guard let memberNames = parseMemberNames(
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
            return []
        }

        let providersByName = Dictionary(
            uniqueKeysWithValues: model.members.map { ($0.name, $0) }
        )
        let unknownNames = memberNames.filter { providersByName[$0] == nil }
        guard unknownNames.isEmpty else {
            for name in unknownNames {
                diagnose(
                    "Multibinding contributor '\(name)' must name a direct @Provide member on this container.",
                    id: "unknown-member",
                    at: Syntax(attribute),
                    in: context
                )
            }
            return []
        }

        let contributors = memberNames.compactMap { providersByName[$0] }
        guard contributors.allSatisfy({ !$0.isAsyncFactory }) else {
            diagnose(
                "The multibinding prototype accepts only synchronous contributors because its generated collection is synchronous.",
                id: "async-member",
                at: Syntax(attribute),
                in: context
            )
            return []
        }

        guard let elementType = contributors.first?.type.trimmedDescription else {
            return []
        }
        let mismatched = contributors.filter {
            $0.type.trimmedDescription != elementType
        }
        guard mismatched.isEmpty else {
            diagnose(
                "Every multibinding contributor must expose the same written type. Expected '\(elementType)', but '\(mismatched[0].name)' exposes '\(mismatched[0].type.trimmedDescription)'.",
                id: "type-mismatch",
                at: Syntax(attribute),
                in: context
            )
            return []
        }

        let accessPrefix = model.accessLevel.map { "\($0) " } ?? ""
        let isolationPrefix = model.options.mainActor
            ? "@_Concurrency.MainActor\n"
            : ""
        let spiPrefix = model.accessLevel == "public"
            ? "@_spi(Experimental)\n"
            : ""
        let elements = contributors.map { "self.\($0.name)" }
            .joined(separator: ",\n        ")
        let declaration: DeclSyntax = """
        \(raw: spiPrefix)\(raw: isolationPrefix)\(raw: accessPrefix)var \(raw: multibindingPrototypeMemberName): [\(raw: elementType)] {
            [
                \(raw: elements)
            ]
        }
        """
        return [
            declaration.prependingMARK(
                "// MARK: - Experimental Multibinding Prototype"
            )
        ]
    }
}

private func parseMemberNames(
    from attribute: AttributeSyntax,
    in context: some MacroExpansionContext
) -> [String]? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          arguments.count == 1,
          let argument = arguments.first,
          argument.label?.text == "members",
          let array = argument.expression.as(ArrayExprSyntax.self) else {
        diagnose(
            "The multibinding prototype requires members: with one literal array of direct provider member names.",
            id: "invalid-members",
            at: Syntax(attribute),
            in: context
        )
        return nil
    }

    var names: [String] = []
    for element in array.elements {
        guard let name = stringLiteralValue(element.expression) else {
            diagnose(
                "Each multibinding contributor must be a plain string literal naming one direct provider member.",
                id: "invalid-members",
                at: Syntax(element.expression),
                in: context
            )
            return nil
        }
        names.append(name)
    }

    guard !names.isEmpty else {
        diagnose(
            "The multibinding prototype requires at least one contributor.",
            id: "empty-members",
            at: Syntax(attribute),
            in: context
        )
        return nil
    }

    var seen: Set<String> = []
    guard names.allSatisfy({ seen.insert($0).inserted }) else {
        diagnose(
            "Each multibinding contributor may appear only once.",
            id: "duplicate-member",
            at: Syntax(attribute),
            in: context
        )
        return nil
    }
    return names
}

private func diagnose(
    _ message: String,
    id: String,
    at node: Syntax,
    in context: some MacroExpansionContext
) {
    context.diagnose(
        Diagnostic(
            node: node,
            message: MultibindingPrototypeDiagnostic(message, id: id)
        )
    )
}

private struct MultibindingPrototypeDiagnostic: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity = .error

    init(_ message: String, id: String) {
        self.message = message
        diagnosticID = MessageID(
            domain: "InnoDI.experimental",
            id: "multibinding-prototype.\(id)"
        )
    }
}
