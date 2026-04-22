//
//  SwiftUIMacros.swift
//  InnoDIMacros
//
//  Phase N-1 — thin helpers shared by `DIEnvironmentBridgeMacro.swift` and
//  `DIFeatureRootMacro.swift`. The macro implementations themselves live in
//  their own files now; this module keeps only the common AST utilities
//  (container member enumeration, nominal-type synthesis, access-level
//  modifier mapping, attribute lookup, feature-root alias validation, etc.).
//

import Foundation
import InnoDICore
import SwiftSyntax
import SwiftSyntaxBuilder

// MARK: - Container shape introspection

internal func containerMemberNames(in declaration: some DeclGroupSyntax) -> [String] {
    declaration.memberBlock.members.compactMap { member in
        guard let variableDecl = member.decl.as(VariableDeclSyntax.self) else {
            return nil
        }
        guard !variableDecl.modifiers.contains(where: { $0.name.text == "static" }) else {
            return nil
        }
        return variableDecl.bindings.first?
            .pattern
            .as(IdentifierPatternSyntax.self)?
            .identifier
            .text
    }
}

internal func nominalTypeSyntax(for declaration: some DeclGroupSyntax) -> TypeSyntax? {
    if let structDecl = declaration.as(StructDeclSyntax.self) {
        return nominalTypeSyntax(name: structDecl.name.text, genericParameterClause: structDecl.genericParameterClause)
    }
    if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return nominalTypeSyntax(name: classDecl.name.text, genericParameterClause: classDecl.genericParameterClause)
    }
    if let actorDecl = declaration.as(ActorDeclSyntax.self) {
        return nominalTypeSyntax(name: actorDecl.name.text, genericParameterClause: actorDecl.genericParameterClause)
    }
    if let enumDecl = declaration.as(EnumDeclSyntax.self) {
        return nominalTypeSyntax(name: enumDecl.name.text, genericParameterClause: enumDecl.genericParameterClause)
    }
    return nil
}

internal func nominalTypeSyntax(
    name: String,
    genericParameterClause: GenericParameterClauseSyntax?
) -> TypeSyntax {
    guard let genericParameterClause else {
        return TypeSyntax(IdentifierTypeSyntax(name: .identifier(name)))
    }

    let genericArguments = GenericArgumentListSyntax(
        genericParameterClause.parameters.enumerated().map { index, parameter in
            GenericArgumentSyntax(
                argument: .type(TypeSyntax(IdentifierTypeSyntax(name: .identifier(parameter.name.text)))),
                trailingComma: index == genericParameterClause.parameters.count - 1 ? nil : .commaToken()
            )
        }
    )
    return TypeSyntax(
        IdentifierTypeSyntax(
            name: .identifier(name),
            genericArgumentClause: GenericArgumentClauseSyntax(arguments: genericArguments)
        )
    )
}

// MARK: - Access level mapping

internal func accessLevelModifierText(for modifiers: DeclModifierListSyntax?) -> String {
    guard let modifiers else {
        return ""
    }

    for modifier in modifiers {
        switch modifier.name.tokenKind {
        case .keyword(.public):
            return "public "
        case .keyword(.package):
            return "package "
        case .keyword(.internal):
            return "internal "
        case .keyword(.fileprivate):
            return "fileprivate "
        case .keyword(.private):
            return "private "
        default:
            continue
        }
    }

    return ""
}

internal func accessLevelModifiers(for modifiers: DeclModifierListSyntax?) -> DeclModifierListSyntax {
    let accessLevel = accessLevelModifierText(for: modifiers).trimmingCharacters(in: .whitespaces)
    guard !accessLevel.isEmpty else {
        return DeclModifierListSyntax([])
    }

    let keyword: TokenSyntax
    switch accessLevel {
    case "public":
        keyword = .keyword(.public)
    case "package":
        keyword = .keyword(.package)
    case "internal":
        keyword = .keyword(.internal)
    case "fileprivate":
        keyword = .keyword(.fileprivate)
    case "private":
        keyword = .keyword(.private)
    default:
        return DeclModifierListSyntax([])
    }

    return DeclModifierListSyntax([
        DeclModifierSyntax(name: keyword)
    ])
}

// MARK: - Attribute lookup

internal func hasAttribute(named name: String, in attributes: AttributeListSyntax?) -> Bool {
    findAttribute(
        named: name,
        allowingQualifiedModules: ["InnoDI"],
        in: attributes
    ) != nil
}

internal func featureRootAttributes(in attributes: AttributeListSyntax?) -> [AttributeSyntax] {
    guard let attributes else {
        return []
    }
    return attributes.compactMap { element -> AttributeSyntax? in
        guard let attribute = element.as(AttributeSyntax.self),
              matchesAttribute(
                named: "DIFeatureRoot",
                attributeName: attribute.attributeName,
                allowingQualifiedModules: ["InnoDISwiftUI"]
              ) else {
            return nil
        }
        return attribute
    }
}

// MARK: - FeatureRoot alias validation

internal func isValidFeatureRootAlias(_ alias: String) -> Bool {
    guard !alias.isEmpty else {
        return false
    }
    guard let firstScalar = alias.unicodeScalars.first,
          isSwiftIdentifierHead(firstScalar) else {
        return false
    }
    return alias.unicodeScalars.dropFirst().allSatisfy(isSwiftIdentifierBody)
}

private func isSwiftIdentifierHead(_ scalar: UnicodeScalar) -> Bool {
    scalar == "_" || CharacterSet.letters.contains(scalar)
}

private func isSwiftIdentifierBody(_ scalar: UnicodeScalar) -> Bool {
    isSwiftIdentifierHead(scalar) || CharacterSet.decimalDigits.contains(scalar)
}

// MARK: - Small AST utilities

internal func stringLiteralValue(_ expression: ExprSyntax) -> String? {
    let text = expression.trimmedDescription
    guard text.count >= 2, text.first == "\"", text.last == "\"" else {
        return nil
    }
    return String(text.dropFirst().dropLast())
}

internal func attributeSortKey(_ attribute: AttributeSyntax) -> Int {
    attribute.positionAfterSkippingLeadingTrivia.utf8Offset
}

internal func enclosingDeclGroup(containing syntax: Syntax) -> (any DeclGroupSyntax)? {
    var current = syntax.parent
    while let node = current {
        if let structDecl = node.as(StructDeclSyntax.self) {
            return structDecl
        }
        if let classDecl = node.as(ClassDeclSyntax.self) {
            return classDecl
        }
        if let actorDecl = node.as(ActorDeclSyntax.self) {
            return actorDecl
        }
        if let enumDecl = node.as(EnumDeclSyntax.self) {
            return enumDecl
        }
        current = node.parent
    }
    return nil
}

internal func enclosingDeclModifiers(containing syntax: Syntax) -> DeclModifierListSyntax? {
    if let enclosingDecl = enclosingDeclGroup(containing: syntax) {
        return enclosingDecl.modifiers
    }
    return nil
}
