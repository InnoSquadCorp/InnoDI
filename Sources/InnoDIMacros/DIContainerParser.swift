import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct DIContainerParser {
    struct OverridesNameConflict {
        let node: any SyntaxProtocol
        let kind: String
    }

    /// Scans the container body for a user declaration named `Overrides` that
    /// would clash with the synthesized builder struct. Returns the offending
    /// declaration along with its kind ("struct", "class", "typealias", etc.)
    /// so callers can emit a clear warning.
    static func findOverridesNameConflict(in decl: some DeclGroupSyntax) -> OverridesNameConflict? {
        for member in decl.memberBlock.members {
            let d = member.decl
            if let s = d.as(StructDeclSyntax.self), s.name.text == "Overrides" {
                return OverridesNameConflict(node: s, kind: "struct")
            }
            if let c = d.as(ClassDeclSyntax.self), c.name.text == "Overrides" {
                return OverridesNameConflict(node: c, kind: "class")
            }
            if let e = d.as(EnumDeclSyntax.self), e.name.text == "Overrides" {
                return OverridesNameConflict(node: e, kind: "enum")
            }
            if let a = d.as(ActorDeclSyntax.self), a.name.text == "Overrides" {
                return OverridesNameConflict(node: a, kind: "actor")
            }
            if let t = d.as(TypeAliasDeclSyntax.self), t.name.text == "Overrides" {
                return OverridesNameConflict(node: t, kind: "typealias")
            }
        }
        return nil
    }

    static func userDefinedInitializers(in decl: some DeclGroupSyntax) -> [InitializerDeclSyntax] {
        let bodyInitializers = decl.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }

        guard let sourceFile = sourceFile(containing: Syntax(decl)),
              let declarationPath = nominalDeclarationPath(containing: Syntax(decl)) else {
            return bodyInitializers
        }

        let extensionInitializers = sourceFile.statements.compactMap { statement in
            statement.item.as(ExtensionDeclSyntax.self)
        }
        .filter { matchesSameFileContainerExtension($0, declarationPath: declarationPath) }
        .flatMap { extensionDecl in
            extensionDecl.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) }
        }

        return bodyInitializers + extensionInitializers
    }

    static func parse(
        declaration decl: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) -> DIContainerExpansionModel? {
        let options = InnoDICore.parseDIContainerAttribute(decl.attributes) ?? DIContainerAttributeInfo(
            root: false,
            validateDAG: true,
            mainActor: false
        )
        let accessLevel = containerAccessLevel(for: decl)
        var members: [ProvideMemberModel] = []
        var subContainerMembers: [SubContainerMemberModel] = []
        var hadErrors = false

        if options.mainActor, let conflictingActor = detectConflictingGlobalActor(in: decl.attributes) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(decl),
                    message: SimpleDiagnostic.containerMainActorConflict(actorName: conflictingActor)
                )
            )
            hadErrors = true
        }

        for member in decl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            if varDecl.modifiers.contains(where: { $0.name.text == "static" }) {
                continue
            }

            // `@SubContainer` classification lives next to `@Provide` so the
            // two attributes can coexist in the same member scan. When both
            // are present on the same property we emit the dedicated
            // conflict diagnostic and skip the property entirely — the
            // codegen pathway for each attribute is mutually exclusive.
            let provideAttribute = InnoDICore.findInnoDIAttribute(named: "Provide", in: varDecl.attributes)
            let subContainerAttribute = InnoDICore.findInnoDIAttribute(named: "SubContainer", in: varDecl.attributes)

            if let subAttribute = subContainerAttribute, provideAttribute != nil {
                let memberName = varDecl.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    ?? "<unknown>"
                context.diagnose(
                    Diagnostic(
                        node: Syntax(subAttribute),
                        message: SimpleDiagnostic.subConflictsWithProvide(memberName: memberName)
                    )
                )
                hadErrors = true
                continue
            }

            if let subAttribute = subContainerAttribute {
                guard let validatedBinding = validateBindingForAttribute(
                    varDecl,
                    kind: .subContainer,
                    context: context
                ) else {
                    hadErrors = true
                    continue
                }
                let subArgs = InnoDICore.parseSubContainerArguments(subAttribute)
                let parentDependencyReferences = extractWithDependencyReferences(from: subAttribute)
                let bindingReferences = extractSubContainerBindingReferences(from: subAttribute)
                subContainerMembers.append(
                    SubContainerMemberModel(
                        name: validatedBinding.identifier.identifier.text,
                        type: validatedBinding.typeAnnotation.type,
                        scope: subArgs.scope,
                        scopeName: subArgs.scopeName,
                        scopeExpressionSyntax: extractArgumentExpression(label: "scope", from: subAttribute),
                        parentDependencies: parentDependencyReferences.map(\.name),
                        explicitBindings: bindingReferences,
                        parentDependencyReferences: parentDependencyReferences,
                        attribute: subAttribute,
                        bindingSyntax: validatedBinding.binding
                    )
                )
                continue
            }

            guard let attribute = provideAttribute else {
                continue
            }

            guard let validatedBinding = validateBindingForAttribute(
                varDecl,
                kind: .provide,
                context: context
            ) else {
                hadErrors = true
                continue
            }

            let parseResult = InnoDICore.parseProvideArguments(attribute)
            guard let scope = parseResult.scope else {
                if let name = parseResult.scopeName {
                    context.diagnose(Diagnostic(node: Syntax(attribute), message: SimpleDiagnostic.provideUnknownScope(name)))
                }
                hadErrors = true
                continue
            }

            let closureParameterList: ClosureParameterList
            if let closure = parseResult.factoryExpr?.as(ClosureExprSyntax.self) {
                closureParameterList = parseClosureParameterNames(closure)
            } else if let asyncClosure = parseResult.asyncFactoryExpr?.as(ClosureExprSyntax.self) {
                closureParameterList = parseClosureParameterNames(asyncClosure)
            } else {
                closureParameterList = ClosureParameterList(names: [], references: [], hasWildcard: false)
            }

            let factoryExpressionReferences: [String]
            if let factoryExpr = parseResult.factoryExpr, factoryExpr.as(ClosureExprSyntax.self) == nil {
                factoryExpressionReferences = extractExpressionDependencyReferences(from: factoryExpr)
            } else {
                factoryExpressionReferences = []
            }

            let asyncFactoryExpressionReferences: [String]
            if let asyncFactoryExpr = parseResult.asyncFactoryExpr, asyncFactoryExpr.as(ClosureExprSyntax.self) == nil {
                asyncFactoryExpressionReferences = extractExpressionDependencyReferences(from: asyncFactoryExpr)
            } else {
                asyncFactoryExpressionReferences = []
            }

            let initializerExpr = validatedBinding.binding.initializer?.value
            let initializerReferences = extractExpressionDependencyReferences(from: initializerExpr)
            let withDependencyReferences = extractWithDependencyReferences(from: attribute)

            members.append(
                ProvideMemberModel(
                    name: validatedBinding.identifier.identifier.text,
                    type: validatedBinding.typeAnnotation.type,
                    scope: scope,
                    factory: parseResult.factoryExpr,
                    asyncFactory: parseResult.asyncFactoryExpr,
                    asyncFactoryIsThrowing: parseResult.asyncFactoryIsThrowing,
                    typeExpr: parseResult.typeExpr,
                    initializer: initializerExpr,
                    concreteOptIn: parseResult.concrete,
                    withDependencies: parseResult.dependencies,
                    withDependencyReferences: withDependencyReferences,
                    closureDependencies: closureParameterList.names,
                    closureParameterReferences: closureParameterList.references,
                    closureHasWildcard: closureParameterList.hasWildcard,
                    expressionReferences: deduplicateStrings(factoryExpressionReferences + asyncFactoryExpressionReferences + initializerReferences),
                    attribute: attribute,
                    bindingSyntax: validatedBinding.binding
                )
            )
        }

        if hadErrors {
            return nil
        }

        return DIContainerExpansionModel(
            options: options,
            accessLevel: accessLevel,
            members: members,
            subContainerMembers: subContainerMembers
        )
    }
}

private enum BindingValidationKind {
    case provide
    case subContainer

    var singleBindingDiagnostic: SimpleDiagnostic {
        switch self {
        case .provide:
            return .provideSingleBinding()
        case .subContainer:
            return .subSingleBinding()
        }
    }

    var namedPropertyDiagnostic: SimpleDiagnostic {
        switch self {
        case .provide:
            return .provideNamedPropertyRequired()
        case .subContainer:
            return .subNamedPropertyRequired()
        }
    }

    var explicitTypeDiagnostic: SimpleDiagnostic {
        switch self {
        case .provide:
            return .provideExplicitTypeRequired()
        case .subContainer:
            return .subExplicitTypeRequired()
        }
    }
}

private struct ValidatedVariableBinding {
    let binding: PatternBindingSyntax
    let identifier: IdentifierPatternSyntax
    let typeAnnotation: TypeAnnotationSyntax
}

private func validateBindingForAttribute(
    _ varDecl: VariableDeclSyntax,
    kind: BindingValidationKind,
    context: some MacroExpansionContext
) -> ValidatedVariableBinding? {
    guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else {
        context.diagnose(
            Diagnostic(node: Syntax(varDecl), message: kind.singleBindingDiagnostic)
        )
        return nil
    }

    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
        context.diagnose(
            Diagnostic(node: Syntax(binding.pattern), message: kind.namedPropertyDiagnostic)
        )
        return nil
    }

    guard let typeAnnotation = binding.typeAnnotation else {
        context.diagnose(
            Diagnostic(node: Syntax(binding.pattern), message: kind.explicitTypeDiagnostic)
        )
        return nil
    }

    return ValidatedVariableBinding(
        binding: binding,
        identifier: identifier,
        typeAnnotation: typeAnnotation
    )
}

/// Walks the parent chain of `syntax` upward until it reaches the enclosing
/// `SourceFileSyntax`.
///
/// Returns `nil` when the syntax has already been detached from its source
/// file — this happens under the `SwiftSyntaxMacroExpansion.expand()`
/// pipeline that the `assertMacroExpansion*` helpers drive. Callers must
/// treat a `nil` return as "best-effort, skip silently".
internal func sourceFileSyntax(containing syntax: Syntax) -> SourceFileSyntax? {
    sourceFile(containing: syntax)
}

private func sourceFile(containing syntax: Syntax) -> SourceFileSyntax? {
    var current: Syntax? = syntax

    while let node = current {
        if let sourceFile = node.as(SourceFileSyntax.self) {
            return sourceFile
        }
        current = node.parent
    }

    return nil
}

private func nominalDeclarationPath(containing syntax: Syntax) -> String? {
    var current: Syntax? = syntax
    var components: [String] = []

    while let node = current {
        if let name = nominalDeclarationName(for: node) {
            components.append(name)
        }
        current = node.parent
    }

    guard !components.isEmpty else {
        return nil
    }

    return components.reversed().joined(separator: ".")
}

private func nominalDeclarationName(for syntax: Syntax) -> String? {
    if let structDecl = syntax.as(StructDeclSyntax.self) {
        return structDecl.name.text
    }
    if let classDecl = syntax.as(ClassDeclSyntax.self) {
        return classDecl.name.text
    }
    if let actorDecl = syntax.as(ActorDeclSyntax.self) {
        return actorDecl.name.text
    }
    if let enumDecl = syntax.as(EnumDeclSyntax.self) {
        return enumDecl.name.text
    }
    return nil
}

private func matchesSameFileContainerExtension(_ extensionDecl: ExtensionDeclSyntax, declarationPath: String) -> Bool {
    guard extensionDecl.genericWhereClause == nil else {
        return false
    }

    return normalizedSemanticTypeReference(extensionDecl.extendedType)?.displayPath == declarationPath
}

private func extractArgumentExpression(label: String, from attribute: AttributeSyntax) -> ExprSyntax? {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return nil
    }

    for argument in arguments where argument.label?.text == label {
        return argument.expression
    }

    return nil
}

private func extractWithDependencyReferences(from attribute: AttributeSyntax) -> [WithDependencyReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "with" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return []
        }

        return arrayExpr.elements.compactMap { element in
            guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                  let property = keyPath.components.last?.component.as(KeyPathPropertyComponentSyntax.self)?.declName.baseName.text else {
                return nil
            }
            return WithDependencyReference(name: property, keyPath: keyPath)
        }
    }

    return []
}

private func extractSubContainerBindingReferences(from attribute: AttributeSyntax) -> [SubContainerBindingReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "bindings" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return []
        }

        return arrayExpr.elements.compactMap { element in
            guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                return nil
            }

            var childName: String?
            var parentName: String?
            var childKeyPath: KeyPathExprSyntax?
            var parentKeyPath: KeyPathExprSyntax?

            for tupleElement in tupleExpr.elements {
                guard let label = tupleElement.label?.text,
                      let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self),
                      let property = keyPath.components.last?
                        .component.as(KeyPathPropertyComponentSyntax.self)?
                        .declName.baseName.text else {
                    continue
                }

                switch label {
                case "child":
                    childName = property
                    childKeyPath = keyPath
                case "parent":
                    parentName = property
                    parentKeyPath = keyPath
                default:
                    continue
                }
            }

            guard let childName, let parentName, let childKeyPath, let parentKeyPath else {
                return nil
            }

            return SubContainerBindingReference(
                childInputName: childName,
                parentMemberName: parentName,
                childKeyPath: childKeyPath,
                parentKeyPath: parentKeyPath
            )
        }
    }

    return []
}

private func containerAccessLevel(for decl: some DeclGroupSyntax) -> String? {
    let modifiers = decl.modifiers
    if modifiers.isEmpty {
        return nil
    }
    for modifier in modifiers {
        switch modifier.name.text {
        case "public", "open":
            return "public"
        case "package":
            return "package"
        case "internal", "fileprivate", "private":
            return modifier.name.text
        default:
            continue
        }
    }
    return nil
}

private func detectConflictingGlobalActor(in attributes: AttributeListSyntax?) -> String? {
    guard let attributes else { return nil }
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        guard let attributeName = globalActorAttributeName(from: attr.attributeName) else { continue }
        if attributeName.terminalName == "DIContainer" || attributeName.terminalName == "MainActor" {
            continue
        }
        if attributeName.terminalName.hasSuffix("Actor") {
            return attributeName.sourceSpelling
        }
    }
    return nil
}

private func globalActorAttributeName(
    from attributeName: TypeSyntax
) -> (terminalName: String, sourceSpelling: String)? {
    if let identifier = attributeName.as(IdentifierTypeSyntax.self) {
        return (identifier.name.text, identifier.trimmedDescription)
    }

    if let member = attributeName.as(MemberTypeSyntax.self) {
        return (member.name.text, member.trimmedDescription)
    }

    return nil
}
