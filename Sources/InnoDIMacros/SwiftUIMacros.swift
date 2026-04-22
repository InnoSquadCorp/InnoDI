import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct DIEnvironmentBridgeMacro {}

extension DIEnvironmentBridgeMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let nominalType = nominalTypeSyntax(for: declaration) else {
            return []
        }

        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: true
        )
        guard let mappings = validation.mappings else {
            return []
        }

        let accessLevel = accessLevelModifiers(for: declaration.modifiers)
        let modifierDecl = makeEnvironmentBridgeModifierDecl(
            accessLevel: accessLevel,
            containerType: nominalType,
            mappings: mappings
        )
        let bridgeMethodDecl = makeEnvironmentBridgeHelperDecl(accessLevel: accessLevel)

        return [DeclSyntax(modifierDecl), DeclSyntax(bridgeMethodDecl)]
    }
}

extension DIEnvironmentBridgeMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let validation = validateEnvironmentBridge(
            attribute: node,
            declaration: declaration,
            context: context,
            emitDiagnostics: false
        )
        guard validation.mappings != nil else {
            return []
        }

        return [
            try ExtensionDeclSyntax("extension \(type): DIEnvironmentBridging {}")
        ]
    }
}

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
        let helperName = featureRootHelperName(propertyName: propertyName, alias: info.alias)

        let featureRootAttributes = varDecl.attributes.compactMap { element -> AttributeSyntax? in
            guard let attribute = element.as(AttributeSyntax.self) else {
                return nil
            }
            guard attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "DIFeatureRoot" else {
                return nil
            }
            return attribute
        }

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

private struct EnvironmentBridgeMappingInfo {
    let memberName: String
    let environmentKeyPath: ExprSyntax
}

private struct EnvironmentBridgeValidationResult {
    let mappings: [EnvironmentBridgeMappingInfo]?
}

private struct FeatureRootAttributeInfo {
    let rootViewTypeName: String
    let alias: String?
}

private func validateEnvironmentBridge(
    attribute: AttributeSyntax,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    emitDiagnostics: Bool
) -> EnvironmentBridgeValidationResult {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          let firstArgument = arguments.first,
          let arrayExpr = firstArgument.expression.as(ArrayExprSyntax.self) else {
        if emitDiagnostics {
            context.diagnose(
                Diagnostic(
                    node: Syntax(attribute),
                    message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidArguments()
                )
            )
        }
        return EnvironmentBridgeValidationResult(mappings: nil)
    }

    let memberNames = Set(containerMemberNames(in: declaration))
    var seenMembers: Set<String> = []
    var mappings: [EnvironmentBridgeMappingInfo] = []
    var hadErrors = false

    for element in arrayExpr.elements {
        guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member")
                    )
                )
            }
            hadErrors = true
            continue
        }

        var memberName: String?
        var environmentKeyPath: ExprSyntax?

        for tupleElement in tupleExpr.elements {
            guard let label = tupleElement.label?.text else {
                continue
            }

            switch label {
            case "member":
                guard let parsedMemberName = stringLiteralValue(tupleElement.expression) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "member")
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                memberName = parsedMemberName
            case "environment":
                guard let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self) else {
                    if emitDiagnostics {
                        context.diagnose(
                            Diagnostic(
                                node: Syntax(tupleElement.expression),
                                message: SimpleDiagnostic.swiftUIEnvironmentBridgeInvalidKeyPath(label: "environment")
                            )
                        )
                    }
                    hadErrors = true
                    continue
                }
                environmentKeyPath = ExprSyntax(keyPath)
            default:
                continue
            }
        }

        guard let memberName, let environmentKeyPath else {
            hadErrors = true
            continue
        }

        guard memberNames.contains(memberName) else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeUnknownMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        guard seenMembers.insert(memberName).inserted else {
            if emitDiagnostics {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(element.expression),
                        message: SimpleDiagnostic.swiftUIEnvironmentBridgeDuplicateMember(memberName: memberName)
                    )
                )
            }
            hadErrors = true
            continue
        }

        mappings.append(
            EnvironmentBridgeMappingInfo(
                memberName: memberName,
                environmentKeyPath: environmentKeyPath
            )
        )
    }

    return EnvironmentBridgeValidationResult(mappings: hadErrors ? nil : mappings)
}

private func makeEnvironmentBridgeModifierDecl(
    accessLevel: DeclModifierListSyntax,
    containerType: TypeSyntax,
    mappings: [EnvironmentBridgeMappingInfo]
) -> StructDeclSyntax {
    let containerDecl = VariableDeclSyntax(
        bindingSpecifier: .keyword(.let),
        bindings: PatternBindingListSyntax([
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: .identifier("container")),
                typeAnnotation: TypeAnnotationSyntax(type: containerType)
            )
        ])
    )
    let bodyDecl = FunctionDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("body"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(
                parameters: FunctionParameterListSyntax([
                    FunctionParameterSyntax(
                        firstName: .identifier("content"),
                        colon: .colonToken(),
                        type: TypeSyntax(IdentifierTypeSyntax(name: .identifier("Content")))
                    )
                ])
            ),
            returnClause: ReturnClauseSyntax(type: TypeSyntax(stringLiteral: "some SwiftUI.View"))
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(
                        StmtSyntax(
                            ExpressionStmtSyntax(
                                expression: makeEnvironmentBridgeBodyExpr(mappings: mappings)
                            )
                        )
                    )
                )
            ])
        )
    )

    return StructDeclSyntax(
        modifiers: accessLevel,
        name: .identifier("_InnoDIEnvironmentBridgeModifier"),
        inheritanceClause: InheritanceClauseSyntax(
            inheritedTypes: InheritedTypeListSyntax([
                InheritedTypeSyntax(type: TypeSyntax(stringLiteral: "SwiftUI.ViewModifier"))
            ])
        ),
        memberBlock: MemberBlockSyntax(
            members: MemberBlockItemListSyntax([
                MemberBlockItemSyntax(decl: DeclSyntax(containerDecl)),
                MemberBlockItemSyntax(decl: DeclSyntax(bodyDecl)),
            ])
        )
    )
}

private func makeEnvironmentBridgeHelperDecl(
    accessLevel: DeclModifierListSyntax
) -> FunctionDeclSyntax {
    let modifierType = TypeSyntax(IdentifierTypeSyntax(name: .identifier("_InnoDIEnvironmentBridgeModifier")))
    let callExpr = ExprSyntax(
        FunctionCallExprSyntax(
            calledExpression: ExprSyntax(
                DeclReferenceExprSyntax(baseName: .identifier("_InnoDIEnvironmentBridgeModifier"))
            ),
            leftParen: .leftParenToken(),
            arguments: LabeledExprListSyntax([
                LabeledExprSyntax(
                    label: .identifier("container"),
                    colon: .colonToken(),
                    expression: ExprSyntax(DeclReferenceExprSyntax(baseName: .keyword(.self)))
                )
            ]),
            rightParen: .rightParenToken()
        )
    )

    return FunctionDeclSyntax(
        attributes: AttributeListSyntax([
            .attribute(
                AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("MainActor")))
            )
        ]),
        modifiers: accessLevel,
        name: .identifier("_innodiEnvironmentBridgeModifier"),
        signature: FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax(parameters: []),
            returnClause: ReturnClauseSyntax(type: modifierType)
        ),
        body: CodeBlockSyntax(
            statements: CodeBlockItemListSyntax([
                CodeBlockItemSyntax(
                    item: .stmt(StmtSyntax(ExpressionStmtSyntax(expression: callExpr)))
                )
            ])
        )
    )
}

private func makeEnvironmentBridgeBodyExpr(
    mappings: [EnvironmentBridgeMappingInfo]
) -> ExprSyntax {
    mappings.reduce(
        ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("content")))
    ) { partialResult, mapping in
        let memberAccess = ExprSyntax(
            MemberAccessExprSyntax(
                base: partialResult,
                declName: DeclReferenceExprSyntax(baseName: .identifier("environment"))
            )
        )
        let containerMember = ExprSyntax(
            MemberAccessExprSyntax(
                base: ExprSyntax(DeclReferenceExprSyntax(baseName: .identifier("container"))),
                declName: DeclReferenceExprSyntax(baseName: .identifier(mapping.memberName))
            )
        )

        return ExprSyntax(
            FunctionCallExprSyntax(
                calledExpression: memberAccess,
                leftParen: .leftParenToken(),
                arguments: LabeledExprListSyntax([
                    LabeledExprSyntax(
                        expression: mapping.environmentKeyPath,
                        trailingComma: .commaToken()
                    ),
                    LabeledExprSyntax(expression: containerMember),
                ]),
                rightParen: .rightParenToken()
            )
        )
    }
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

            for attribute in variableDecl.attributes.compactMap({ $0.as(AttributeSyntax.self) }) {
                guard attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "DIFeatureRoot",
                      let info = parseFeatureRootAttribute(attribute) else {
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

private func keyPathComponentName(from expression: ExprSyntax) -> String? {
    expression.as(KeyPathExprSyntax.self)?
        .components
        .last?
        .component
        .as(KeyPathPropertyComponentSyntax.self)?
        .declName
        .baseName
        .text
}

private func containerMemberNames(in declaration: some DeclGroupSyntax) -> [String] {
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

private func nominalTypeSyntax(for declaration: some DeclGroupSyntax) -> TypeSyntax? {
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

private func nominalTypeSyntax(
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

private func accessLevelModifierText(for modifiers: DeclModifierListSyntax?) -> String {
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

private func accessLevelModifiers(for modifiers: DeclModifierListSyntax?) -> DeclModifierListSyntax {
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

private func hasAttribute(named name: String, in attributes: AttributeListSyntax?) -> Bool {
    attributes?.contains(where: { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.as(IdentifierTypeSyntax.self)?.name.text == name
    }) == true
}

private func stringLiteralValue(_ expression: ExprSyntax) -> String? {
    let text = expression.trimmedDescription
    guard text.count >= 2, text.first == "\"", text.last == "\"" else {
        return nil
    }
    return String(text.dropFirst().dropLast())
}

private func attributeSortKey(_ attribute: AttributeSyntax) -> Int {
    attribute.positionAfterSkippingLeadingTrivia.utf8Offset
}

private func enclosingDeclGroup(containing syntax: Syntax) -> (any DeclGroupSyntax)? {
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

private func enclosingDeclModifiers(containing syntax: Syntax) -> DeclModifierListSyntax? {
    if let enclosingDecl = enclosingDeclGroup(containing: syntax) {
        return enclosingDecl.modifiers
    }
    return nil
}
