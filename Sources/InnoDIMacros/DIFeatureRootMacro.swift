//
//  DIFeatureRootMacro.swift
//  InnoDIMacros
//
//  Phase N-1 — extracted from `SwiftUIMacros.swift`.
//
//  `@DIFeatureRoot` pairs a `@SubContainer`-backed property with a SwiftUI
//  root view type and emits a helper function (e.g. `featureRootView()`)
//  that instantiates the root view with the sub-container injected. The
//  attribute is restricted to declarations that also carry `@SubContainer`,
//  and multiple aliases on one property are disambiguated by the `as:`
//  argument.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIFeatureRootMacro {}

extension DIFeatureRootMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let varDecl = declaration.as(VariableDeclSyntax.self),
              varDecl.bindings.count == 1,
              let binding = varDecl.bindings.first,
              let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
              let typeAnnotation = binding.typeAnnotation,
              let info = parseFeatureRootAttribute(node) else {
            return []
        }

        guard hasAttribute(named: "SubContainer", in: varDecl.attributes) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.swiftUIFeatureRootWithoutSubContainer()
                )
            )
            return []
        }

        let propertyName = identifier.identifier.text
        if let invalidAlias = info.invalidAliasText {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.swiftUIFeatureRootInvalidAlias(alias: invalidAlias)
                )
            )
            return []
        }
        if let alias = info.validAlias, !isValidFeatureRootAlias(alias) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.swiftUIFeatureRootInvalidAlias(alias: alias)
                )
            )
            return []
        }
        let helperName = featureRootHelperName(propertyName: propertyName, alias: info.validAlias)

        let featureRootAttributes = featureRootAttributes(in: varDecl.attributes)

        if info.validAlias == nil, info.invalidAliasText == nil {
            let aliaslessAttributes = featureRootAttributes.filter {
                guard let parsed = parseFeatureRootAttribute($0) else {
                    return false
                }
                return parsed.validAlias == nil && parsed.invalidAliasText == nil
            }
            if let currentIndex = aliaslessAttributes.firstIndex(where: { $0 == node }),
               currentIndex > 0 {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(node),
                        message: SimpleDiagnostic.swiftUIFeatureRootDuplicateDefault(propertyName: propertyName)
                    )
                )
                return []
            }
        }

        if let enclosingDecl = enclosingDeclGroup(in: context),
           featureRootHelperConflicts(
                helperName: helperName,
                currentAttribute: node,
                in: enclosingDecl
           ) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.swiftUIFeatureRootHelperNameConflict(helperName: helperName)
                )
            )
            return []
        }

        let accessLevel = accessLevelModifierText(for: enclosingDeclGroup(in: context)?.modifiers)
        let childTypeName = typeAnnotation.type.trimmedDescription
        let rootViewTypeName = info.rootViewTypeName

        let helperDecl: DeclSyntax = """
            \(raw: accessLevel)func \(raw: helperName)() -> \(raw: rootViewTypeName) {
                \(raw: rootViewTypeName)(container: \(raw: propertyName))
            }
            """

        _ = childTypeName
        return [helperDecl]
    }
}

// MARK: - Attribute parsing

private struct FeatureRootAttributeInfo {
    let rootViewTypeName: String
    let validAlias: String?
    let invalidAliasText: String?
}

private func parseFeatureRootAttribute(_ attribute: AttributeSyntax) -> FeatureRootAttributeInfo? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return nil
    }

    var rootViewTypeName: String?
    var validAlias: String?
    var invalidAliasText: String?

    for argument in arguments {
        if let label = argument.label?.text {
            if label == "as" {
                if let alias = stringLiteralValue(argument.expression) {
                    validAlias = alias
                    invalidAliasText = nil
                } else {
                    validAlias = nil
                    invalidAliasText = argument.expression.trimmedDescription
                }
            }
            continue
        }

        if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self),
           memberAccess.declName.baseName.text == "self",
           let base = memberAccess.base {
            rootViewTypeName = base.trimmedDescription
        } else if argument.expression.trimmedDescription.hasSuffix(".self") {
            rootViewTypeName = String(argument.expression.trimmedDescription.dropLast(5))
        }
    }

    guard let rootViewTypeName else {
        return nil
    }

    return FeatureRootAttributeInfo(
        rootViewTypeName: rootViewTypeName,
        validAlias: validAlias,
        invalidAliasText: invalidAliasText
    )
}

private func featureRootHelperName(propertyName: String, alias: String?) -> String {
    if let alias, !alias.isEmpty {
        return "\(alias)RootView"
    }
    return "\(propertyName)RootView"
}

private func featureRootHelperConflicts(
    helperName: String,
    currentAttribute: AttributeSyntax,
    in declaration: any DeclGroupSyntax
) -> Bool {
    for member in declaration.memberBlock.members {
        let decl = member.decl

        if let functionDecl = decl.as(FunctionDeclSyntax.self),
           functionDecl.name.text == helperName {
            return true
        }

        if let variableDecl = decl.as(VariableDeclSyntax.self) {
            if variableDecl.bindings.contains(where: {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == helperName
            }) {
                return true
            }

            for attribute in featureRootAttributes(in: variableDecl.attributes) {
                guard let info = parseFeatureRootAttribute(attribute) else {
                    continue
                }
                if info.invalidAliasText != nil {
                    continue
                }
                if let alias = info.validAlias, !isValidFeatureRootAlias(alias) {
                    continue
                }

                guard variableDecl.bindings.count == 1,
                      let propertyName = variableDecl.bindings.first?
                        .pattern.as(IdentifierPatternSyntax.self)?
                        .identifier.text else {
                    continue
                }
                let candidateName = featureRootHelperName(propertyName: propertyName, alias: info.validAlias)
                if candidateName == helperName,
                   attribute != currentAttribute,
                   attributeSortKey(attribute) < attributeSortKey(currentAttribute) {
                    return true
                }
            }
        }
    }

    return false
}

private func enclosingDeclGroup(in context: some MacroExpansionContext) -> (any DeclGroupSyntax)? {
    for node in context.lexicalContext.reversed() {
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
    }

    return nil
}
