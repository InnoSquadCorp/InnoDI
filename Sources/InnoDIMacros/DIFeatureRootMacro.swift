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
        if let alias = info.alias, !isValidFeatureRootAlias(alias) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: SimpleDiagnostic.swiftUIFeatureRootInvalidAlias(alias: alias)
                )
            )
            return []
        }
        let helperName = featureRootHelperName(propertyName: propertyName, alias: info.alias)

        let featureRootAttributes = featureRootAttributes(in: varDecl.attributes)

        if info.alias == nil {
            let aliaslessAttributes = featureRootAttributes.filter {
                parseFeatureRootAttribute($0)?.alias == nil
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

        if let enclosingDecl = enclosingDeclGroup(containing: Syntax(declaration)),
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

        let accessLevel = accessLevelModifierText(for: enclosingDeclModifiers(containing: Syntax(declaration)))
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
    let alias: String?
}

private func parseFeatureRootAttribute(_ attribute: AttributeSyntax) -> FeatureRootAttributeInfo? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return nil
    }

    var rootViewTypeName: String?
    var alias: String?

    for argument in arguments {
        if let label = argument.label?.text {
            if label == "as" {
                alias = stringLiteralValue(argument.expression)
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

    return FeatureRootAttributeInfo(rootViewTypeName: rootViewTypeName, alias: alias)
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
                if let alias = info.alias, !isValidFeatureRootAlias(alias) {
                    continue
                }

                let propertyName = variableDecl.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?
                    .identifier.text
                    ?? ""
                let candidateName = featureRootHelperName(propertyName: propertyName, alias: info.alias)
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
