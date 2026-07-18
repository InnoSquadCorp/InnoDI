import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct FeatureRootParseResult {
    let roots: [FeatureRootMemberModel]
    let hadErrors: Bool
}

private struct ParsedFeatureRootArgument {
    let root: FeatureRootMemberModel?
    let invalidAliasText: String?
    let aliasAnchor: Syntax?
    let invalidRootAnchor: Syntax?
}

func extractFeatureRootReferences(
    from attribute: AttributeSyntax,
    propertyName: String,
    existingSubContainers: [SubContainerMemberModel],
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> FeatureRootParseResult {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return FeatureRootParseResult(roots: [], hadErrors: false)
    }

    var roots: [FeatureRootMemberModel] = []
    var hadErrors = false

    for argument in arguments {
        guard let label = argument.label?.text else { continue }

        switch label {
        case "featureRoot":
            if argument.expression.is(NilLiteralExprSyntax.self) {
                continue
            }
            guard let rootViewTypeName = parseFeatureRootTypeName(from: argument.expression) else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument.expression),
                        message: SimpleDiagnostic.swiftUIFeatureRootInvalidRoot()
                    )
                )
                hadErrors = true
                continue
            }
            roots.append(
                FeatureRootMemberModel(
                    rootViewTypeName: rootViewTypeName,
                    alias: nil,
                    propertyName: propertyName,
                    anchorSyntax: Syntax(argument.expression)
                )
            )

        case "featureRoots":
            guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(argument.expression),
                        message: SimpleDiagnostic.swiftUIFeatureRootInvalidRoot()
                    )
                )
                hadErrors = true
                continue
            }

            for element in arrayExpr.elements {
                let parsed = parseFeatureRootInitializer(
                    element.expression,
                    propertyName: propertyName
                )
                if let invalidRootAnchor = parsed.invalidRootAnchor {
                    context.diagnose(
                        Diagnostic(
                            node: invalidRootAnchor,
                            message: SimpleDiagnostic.swiftUIFeatureRootInvalidRoot()
                        )
                    )
                    hadErrors = true
                    continue
                }
                if let invalidAliasText = parsed.invalidAliasText {
                    context.diagnose(
                        Diagnostic(
                            node: parsed.aliasAnchor ?? Syntax(element.expression),
                            message: SimpleDiagnostic.swiftUIFeatureRootInvalidAlias(
                                alias: invalidAliasText
                            )
                        )
                    )
                    hadErrors = true
                    continue
                }
                if let root = parsed.root {
                    roots.append(root)
                }
            }

        default:
            continue
        }
    }

    let defaultRoots = roots.filter { $0.alias == nil }
    if defaultRoots.count > 1 {
        for root in defaultRoots.dropFirst() {
            context.diagnose(
                Diagnostic(
                    node: root.anchorSyntax,
                    message: SimpleDiagnostic.swiftUIFeatureRootDuplicateDefault(
                        propertyName: propertyName
                    )
                )
            )
        }
        hadErrors = true
    }
    if hadErrors {
        return FeatureRootParseResult(roots: roots, hadErrors: true)
    }

    var seenHelpers: Set<String> = []
    for root in roots {
        if !seenHelpers.insert(root.helperName).inserted {
            context.diagnose(
                Diagnostic(
                    node: root.anchorSyntax,
                    message: SimpleDiagnostic.swiftUIFeatureRootHelperNameConflict(
                        helperName: root.helperName
                    )
                )
            )
            hadErrors = true
        }
        if featureRootHelperConflicts(
            helperName: root.helperName,
            existingSubContainers: existingSubContainers,
            in: declaration
        ) {
            context.diagnose(
                Diagnostic(
                    node: root.anchorSyntax,
                    message: SimpleDiagnostic.swiftUIFeatureRootHelperNameConflict(
                        helperName: root.helperName
                    )
                )
            )
            hadErrors = true
        }
    }

    return FeatureRootParseResult(roots: roots, hadErrors: hadErrors)
}

private func parseFeatureRootInitializer(
    _ expression: ExprSyntax,
    propertyName: String
) -> ParsedFeatureRootArgument {
    guard let call = expression.as(FunctionCallExprSyntax.self),
          isFeatureRootInitializerCallee(call.calledExpression) else {
        return ParsedFeatureRootArgument(
            root: nil,
            invalidAliasText: nil,
            aliasAnchor: nil,
            invalidRootAnchor: Syntax(expression)
        )
    }

    var rootViewTypeName: String?
    var alias: String?
    var invalidAliasText: String?
    var aliasAnchor: Syntax?

    for argument in call.arguments {
        if let label = argument.label?.text {
            if label == "as" {
                aliasAnchor = Syntax(argument.expression)
                if let value = stringLiteralValue(argument.expression),
                   isValidFeatureRootAlias(value) {
                    alias = value
                } else {
                    invalidAliasText = stringLiteralValue(argument.expression)
                        ?? argument.expression.trimmedDescription
                }
            }
            continue
        }

        if rootViewTypeName == nil {
            rootViewTypeName = parseFeatureRootTypeName(from: argument.expression)
        }
    }

    guard let rootViewTypeName else {
        return ParsedFeatureRootArgument(
            root: nil,
            invalidAliasText: nil,
            aliasAnchor: nil,
            invalidRootAnchor: Syntax(expression)
        )
    }

    if let invalidAliasText {
        return ParsedFeatureRootArgument(
            root: nil,
            invalidAliasText: invalidAliasText,
            aliasAnchor: aliasAnchor,
            invalidRootAnchor: nil
        )
    }

    return ParsedFeatureRootArgument(
        root: FeatureRootMemberModel(
            rootViewTypeName: rootViewTypeName,
            alias: alias,
            propertyName: propertyName,
            anchorSyntax: Syntax(expression)
        ),
        invalidAliasText: nil,
        aliasAnchor: nil,
        invalidRootAnchor: nil
    )
}

private func parseFeatureRootTypeName(from expression: ExprSyntax) -> String? {
    if let memberAccess = expression.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "self",
       let base = memberAccess.base {
        return base.trimmedDescription
    }

    let description = expression.trimmedDescription
    guard description.hasSuffix(".self") else {
        return nil
    }
    return String(description.dropLast(5))
}

private func isFeatureRootInitializerCallee(_ expression: ExprSyntax) -> Bool {
    let description = expression.trimmedDescription
    return description == "FeatureRoot" || description.hasSuffix(".FeatureRoot")
}

private func featureRootHelperConflicts(
    helperName: String,
    existingSubContainers: [SubContainerMemberModel],
    in declaration: some DeclGroupSyntax
) -> Bool {
    if existingSubContainers.contains(where: { member in
        member.featureRoots.contains(where: { $0.helperName == helperName })
    }) {
        return true
    }

    return directContainerDeclarationNames(in: declaration).contains {
        $0.namespace == .value && $0.name == helperName
    }
}
