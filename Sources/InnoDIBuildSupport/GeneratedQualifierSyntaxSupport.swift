import InnoDICore
import SwiftSyntax

// Pure syntax normalization used while collecting generated-qualifier inputs.
func environmentBridgeAttribute(
    in attributes: AttributeListSyntax?
) -> AttributeSyntax? {
    findAttribute(
        named: "DIEnvironmentBridge",
        allowingQualifiedModules: ["InnoDISwiftUI"],
        in: attributes
    )
}

func hasAttribute(
    named expectedName: String,
    in attributes: AttributeListSyntax?
) -> Bool {
    attributes?.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.trimmedDescription == expectedName
    } ?? false
}

func spiGroups(
    in attributes: AttributeListSyntax?
) -> Set<String> {
    Set(
        attributes?.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self),
                  attribute.attributeName.trimmedDescription == "_spi",
                  let argument = attribute.arguments?
                    .as(LabeledExprListSyntax.self)?
                    .first?
                    .expression
                    .trimmedDescription,
                  !argument.isEmpty else {
                return nil
            }
            return unescapedIdentifier(argument)
        } ?? []
    )
}

func declarationAccess(
    _ modifiers: DeclModifierListSyntax,
    defaultAccess: QualifierDeclarationAccess = .internal
) -> QualifierDeclarationAccess {
    func hasDeclarationModifier(_ name: String) -> Bool {
        modifiers.contains {
            $0.name.text == name && $0.detail == nil
        }
    }

    if hasDeclarationModifier("private") {
        return .private
    }
    if hasDeclarationModifier("fileprivate") {
        return .fileprivate
    }
    if hasDeclarationModifier("open")
        || hasDeclarationModifier("public") {
        return .public
    }
    if hasDeclarationModifier("package") {
        return .package
    }
    if hasDeclarationModifier("internal") {
        return .internal
    }
    return defaultAccess
}

func declarationModifiers(
    _ declaration: some DeclGroupSyntax
) -> DeclModifierListSyntax {
    if let declaration = declaration.as(StructDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(ClassDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(EnumDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(ActorDeclSyntax.self) {
        return declaration.modifiers
    }
    if let declaration = declaration.as(ProtocolDeclSyntax.self) {
        return declaration.modifiers
    }
    return []
}

func normalizedQualifierTypeReference(
    _ type: TypeSyntax
) -> SemanticTypeReference? {
    if let reference = normalizedSemanticTypeReference(type) {
        return reference
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.firstName == nil,
       element.secondName == nil {
        return normalizedQualifierTypeReference(element.type)
    }
    return nil
}

func normalizedQualifierInheritanceReference(
    _ type: TypeSyntax
) -> SemanticTypeReference? {
    if let reference = normalizedQualifierTypeReference(type) {
        return reference
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedQualifierInheritanceReference(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let element = tuple.elements.first,
       element.firstName == nil,
       element.secondName == nil {
        return normalizedQualifierInheritanceReference(element.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return SemanticTypeReference(
            displayPath: identifier.name.text,
            components: [identifier.name.text]
        )
    }
    if let member = type.as(MemberTypeSyntax.self),
       let base = normalizedQualifierInheritanceReference(member.baseType) {
        let components = base.components + [member.name.text]
        return SemanticTypeReference(
            displayPath: components.joined(separator: "."),
            components: components
        )
    }
    return nil
}

func identifierPatternTokens(
    in syntax: Syntax
) -> [TokenSyntax] {
    if let identifier = syntax.as(IdentifierPatternSyntax.self) {
        return [identifier.identifier]
    }
    return syntax.children(viewMode: .sourceAccurate).flatMap {
        identifierPatternTokens(in: $0)
    }
}

func unescapedIdentifier(_ spelling: String) -> String {
    guard spelling.count >= 2,
          spelling.first == "`",
          spelling.last == "`" else {
        return spelling
    }
    return String(spelling.dropFirst().dropLast())
}
