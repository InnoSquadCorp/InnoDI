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
    /// so callers can emit a clear error. Top-level conditional-compilation
    /// branches participate in the same member lookup scope, while nested type
    /// bodies stop at their own declaration.
    static func findOverridesNameConflict(in decl: some DeclGroupSyntax) -> OverridesNameConflict? {
        for member in decl.memberBlock.members {
            if let conflict = findOverridesNameConflict(in: Syntax(member.decl)) {
                return conflict
            }
        }
        return nil
    }

    private static func findOverridesNameConflict(
        in syntax: Syntax
    ) -> OverridesNameConflict? {
        func matches(_ token: TokenSyntax) -> Bool {
            unescapedInnoDIIdentifierName(token) == "Overrides"
        }

        if let declaration = syntax.as(StructDeclSyntax.self) {
            return matches(declaration.name)
                ? OverridesNameConflict(node: declaration, kind: "struct")
                : nil
        }
        if let declaration = syntax.as(ClassDeclSyntax.self) {
            return matches(declaration.name)
                ? OverridesNameConflict(node: declaration, kind: "class")
                : nil
        }
        if let declaration = syntax.as(EnumDeclSyntax.self) {
            return matches(declaration.name)
                ? OverridesNameConflict(node: declaration, kind: "enum")
                : nil
        }
        if let declaration = syntax.as(ActorDeclSyntax.self) {
            return matches(declaration.name)
                ? OverridesNameConflict(node: declaration, kind: "actor")
                : nil
        }
        if let declaration = syntax.as(ProtocolDeclSyntax.self) {
            return matches(declaration.name)
                ? OverridesNameConflict(node: declaration, kind: "protocol")
                : nil
        }
        if let declaration = syntax.as(TypeAliasDeclSyntax.self) {
            return matches(declaration.name)
                ? OverridesNameConflict(node: declaration, kind: "typealias")
                : nil
        }

        guard syntax.is(IfConfigDeclSyntax.self)
            || syntax.is(IfConfigClauseListSyntax.self)
            || syntax.is(IfConfigClauseSyntax.self)
            || syntax.is(MemberBlockItemSyntax.self)
            || syntax.is(MemberBlockItemListSyntax.self) else {
            return nil
        }
        for child in syntax.children(viewMode: .sourceAccurate) {
            if let conflict = findOverridesNameConflict(in: child) {
                return conflict
            }
        }
        return nil
    }

    static func userDefinedInitializers(in decl: some DeclGroupSyntax) -> [InitializerDeclSyntax] {
        let bodyInitializers = directInitializers(
            in: decl.memberBlock.members
        )

        guard let sourceFile = sourceFile(containing: Syntax(decl)),
              let declarationPath = nominalDeclarationPath(containing: Syntax(decl)) else {
            return bodyInitializers
        }

        let extensionInitializers = sourceFile.statements.compactMap { statement in
            statement.item.as(ExtensionDeclSyntax.self)
        }
        .filter { matchesSameFileContainerExtension($0, declarationPath: declarationPath) }
        .flatMap { extensionDecl in
            directInitializers(in: extensionDecl.memberBlock.members)
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
        var firstManagedIdentifierByName: [String: TokenSyntax] = [:]
        var hadErrors = false

        if diagnoseInvalidContainerBoolArguments(
            options: options,
            declaration: decl,
            context: context
        ) {
            hadErrors = true
        }

        if options.mainActor, let conflictingActor = detectConflictingGlobalActor(in: decl.attributes) {
            context.diagnose(
                Diagnostic(
                    node: Syntax(decl),
                    message: SimpleDiagnostic.containerMainActorConflict(actorName: conflictingActor)
                )
            )
            hadErrors = true
        }

        for member in unmanagedStoredContainerMembers(in: decl) {
            context.diagnose(
                Diagnostic(
                    node: member.anchor,
                    message: SimpleDiagnostic.containerUnmanagedStoredProperty(
                        memberName: member.name
                    )
                )
            )
            hadErrors = true
        }

        for conditionalMember in conditionallyCompiledProvideMembers(in: decl) {
            let memberName = conditionalMember.declaration.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                ?? "<unknown>"
            context.diagnose(
                Diagnostic(
                    node: Syntax(conditionalMember.attribute),
                    message: SimpleDiagnostic.provideConditionalDeclarationUnsupported(
                        memberName: memberName
                    )
                )
            )
            hadErrors = true
        }

        for conditionalMember in conditionallyCompiledSubContainerMembers(in: decl) {
            let memberName = conditionalMember.declaration.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                ?? "<unknown>"
            context.diagnose(
                Diagnostic(
                    node: Syntax(conditionalMember.attribute),
                    message: SimpleDiagnostic.subConditionalDeclarationUnsupported(
                        memberName: memberName
                    )
                )
            )
            hadErrors = true
        }

        for (sourceOrder, member) in decl.memberBlock.members.enumerated() {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            if findInnoDIAttribute(
                named: "_InnoDIProvideAccessor",
                in: varDecl.attributes
            ) != nil || findInnoDIAttribute(
                named: "_InnoDISubContainerAccessor",
                in: varDecl.attributes
            ) != nil {
                // The member-attribute role owns the manual-attachment
                // diagnostic. Exclude every forged support owner before
                // either public managed-member model can reach codegen.
                hadErrors = true
                continue
            }

            let provideAttributes = findInnoDIAttributes(
                named: "Provide",
                in: varDecl.attributes
            )
            if provideAttributes.count > 1 {
                // The second public @Provide peer owns the one global
                // diagnostic, including outside a container. The parser only
                // fails closed so code generation cannot see this member.
                hadErrors = true
                continue
            }

            // `@SubContainer` classification lives next to `@Provide` so the
            // two attributes can coexist in the same member scan. When both
            // are present on the same property we emit the dedicated
            // conflict diagnostic and skip the property entirely — the
            // codegen pathway for each attribute is mutually exclusive.
            let provideAttribute = provideAttributes.first
            let subContainerAttributes = findInnoDIAttributes(
                named: "SubContainer",
                in: varDecl.attributes
            )
            if subContainerAttributes.count > 1 {
                hadErrors = true
                continue
            }
            let subContainerAttribute = subContainerAttributes.first
            let isDependencyMember = provideAttribute != nil || subContainerAttribute != nil

            if varDecl.modifiers.contains(where: { $0.name.text == "static" }),
               subContainerAttribute == nil {
                // Public @Provide owns its plain-instance-member diagnostic.
                // A static @SubContainer must continue through the child
                // declaration validator below so it cannot disappear without
                // the documented InnoDI usage error.
                continue
            }

            if options.mainActor, isDependencyMember {
                if let conflictingActor = detectConflictingGlobalActor(
                    in: varDecl.attributes
                ) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(varDecl),
                            message: SimpleDiagnostic.containerMainActorConflict(
                                actorName: conflictingActor
                            )
                        )
                    )
                    hadErrors = true
                    continue
                }

                if varDecl.modifiers.contains(where: { $0.name.text == "nonisolated" }) {
                    let memberName = varDecl.bindings.first?
                        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                        ?? "<unknown>"
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(varDecl),
                            message: SimpleDiagnostic.containerMainActorNonisolatedMember(
                                memberName: memberName
                            )
                        )
                    )
                    hadErrors = true
                    continue
                }
            }

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
                if isEscapedInnoDIIdentifier(
                    validatedBinding.identifier.identifier
                ) {
                    // Public @SubContainer owns the single escaped-name
                    // diagnostic. Hidden child support is never attached.
                    hadErrors = true
                    continue
                }
                guard isSupportedSubContainerStoredProperty(varDecl) else {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(subAttribute),
                            message: SimpleDiagnostic.subRequiresDirectContainerMember(
                                memberName: validatedBinding.identifier.identifier.text
                            )
                        )
                    )
                    // Fail the model before hidden support or container init
                    // code can reference missing peers.
                    hadErrors = true
                    continue
                }
                let subArgs = InnoDICore.parseSubContainerArguments(subAttribute)
                let parentDependencyReferences = extractWithDependencyReferences(from: subAttribute)
                let bindingReferences = extractSubContainerBindingReferences(from: subAttribute)
                let invalidBindingReferences = extractInvalidSubContainerBindingReferences(from: subAttribute)
                let memberName = validatedBinding.identifier.identifier.text
                if diagnoseDuplicateManagedMemberName(
                    memberName,
                    identifier: validatedBinding.identifier.identifier,
                    firstIdentifierByName: &firstManagedIdentifierByName,
                    context: context
                ) {
                    hadErrors = true
                    continue
                }
                let featureRoots = extractFeatureRootReferences(
                    from: subAttribute,
                    propertyName: memberName,
                    existingSubContainers: subContainerMembers,
                    declaration: decl,
                    context: context
                )
                if featureRoots.hadErrors {
                    hadErrors = true
                    continue
                }
                subContainerMembers.append(
                    SubContainerMemberModel(
                        sourceOrder: sourceOrder,
                        name: memberName,
                        type: validatedBinding.typeAnnotation.type,
                        scope: subArgs.scope,
                        scopeName: subArgs.scopeName,
                        scopeExpressionSyntax: extractArgumentExpression(label: "scope", from: subAttribute),
                        parentDependencies: subArgs.dependencies,
                        hasWithDependencies: subArgs.hasWithDependencies,
                        sameNameWiring: subArgs.sameNameWiring,
                        sameNameWiringExpressionSyntax: sameNameWiringExpressionSyntax(
                            for: subArgs.sameNameWiring,
                            in: subAttribute
                        ),
                        explicitBindings: bindingReferences,
                        invalidBindingReferences: invalidBindingReferences,
                        bindingsParseState: subArgs.bindingsParseState,
                        parentDependencyReferences: parentDependencyReferences,
                        featureRoots: featureRoots.roots,
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

            // Public `@Provide` owns the single declaration-shape diagnostic.
            // Validate binding arity/name/type first so those established,
            // more-specific diagnostics remain reachable without attaching an
            // accessor to an unsafe declaration.
            guard isSupportedProvideStoredProperty(varDecl) else {
                hadErrors = true
                continue
            }

            if isEscapedInnoDIIdentifier(
                validatedBinding.identifier.identifier
            ) {
                // The public @Provide peer owns the single diagnostic while
                // the member-attribute recovery bit suppresses hidden storage.
                hadErrors = true
                continue
            }

            let memberName = validatedBinding.identifier.identifier.text
            if diagnoseDuplicateManagedMemberName(
                memberName,
                identifier: validatedBinding.identifier.identifier,
                firstIdentifierByName: &firstManagedIdentifierByName,
                context: context
            ) {
                hadErrors = true
                continue
            }

            let parseResult = InnoDICore.parseProvideArguments(attribute)
            let withDependencyReferences = extractWithDependencyReferences(
                from: attribute,
                requiringCanonicalProvidePath: true
            )
            var memberHadErrors = false
            if parseResult.concreteParseState.isInvalid {
                context.diagnose(
                    Diagnostic(
                        node: extractArgumentExpression(label: "concrete", from: attribute).map(Syntax.init) ?? Syntax(attribute),
                        message: SimpleDiagnostic.provideBoolLiteralRequired(label: "concrete")
                    )
                )
                memberHadErrors = true
            }
            if parseResult.escapingParseState.isInvalid {
                context.diagnose(
                    Diagnostic(
                        node: extractArgumentExpression(label: "escaping", from: attribute).map(Syntax.init) ?? Syntax(attribute),
                        message: SimpleDiagnostic.provideBoolLiteralRequired(label: "escaping")
                    )
                )
                memberHadErrors = true
            }
            if parseResult.dependenciesParseState.isInvalid {
                context.diagnose(
                    Diagnostic(
                        node: extractArgumentExpression(label: "with", from: attribute).map(Syntax.init) ?? Syntax(attribute),
                        message: SimpleDiagnostic.provideInvalidWithDependencies(
                            memberName: memberName,
                            expectedRoot: "Self"
                        )
                    )
                )
                memberHadErrors = true
            }
            if memberHadErrors {
                hadErrors = true
                continue
            }
            guard let scope = parseResult.scope else {
                // `ProvideMacro` owns the terminal unknown-scope diagnostic so
                // standalone uses and container members share one path without
                // duplicate errors. The container parser still fails closed
                // and omits the invalid member from generated scaffolding.
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

            let initializerExpr = validatedBinding.binding.initializer?.value
            members.append(
                ProvideMemberModel(
                    sourceOrder: sourceOrder,
                    name: memberName,
                    type: validatedBinding.typeAnnotation.type,
                    scope: scope,
                    factory: parseResult.factoryExpr,
                    asyncFactory: parseResult.asyncFactoryExpr,
                    asyncFactoryIsThrowing: parseResult.asyncFactoryIsThrowing,
                    typeExpr: parseResult.typeExpr,
                    initializer: initializerExpr,
                    concreteOptIn: parseResult.concrete,
                    concreteParseState: parseResult.concreteParseState,
                    escapingInput: parseResult.escaping,
                    escapingParseState: parseResult.escapingParseState,
                    withDependencies: parseResult.dependencies,
                    withDependenciesParseState: parseResult.dependenciesParseState,
                    withDependencyReferences: withDependencyReferences,
                    closureDependencies: closureParameterList.names,
                    closureParameterReferences: closureParameterList.references,
                    closureHasWildcard: closureParameterList.hasWildcard,
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

private func diagnoseDuplicateManagedMemberName(
    _ memberName: String,
    identifier: TokenSyntax,
    firstIdentifierByName: inout [String: TokenSyntax],
    context: some MacroExpansionContext
) -> Bool {
    guard let firstIdentifier = firstIdentifierByName[memberName] else {
        firstIdentifierByName[memberName] = identifier
        return false
    }

    context.diagnose(
        Diagnostic(
            node: Syntax(identifier),
            message: SimpleDiagnostic.containerDuplicateMemberName(
                memberName: memberName
            ),
            notes: [
                Note(
                    node: Syntax(firstIdentifier),
                    message: SimpleNote(
                        "The first managed dependency member named '\(memberName)' is declared here.",
                        code: .containerDuplicateMemberName,
                        suffix: "first-declaration"
                    )
                )
            ]
        )
    )
    return true
}

/// Collects initializers declared directly in a container or its matching
/// same-file extension. Conditional-compilation branches share the surrounding
/// member scope, while nested declarations and executable bodies do not.
private func directInitializers(
    in members: MemberBlockItemListSyntax
) -> [InitializerDeclSyntax] {
    var result: [InitializerDeclSyntax] = []
    for member in members {
        collectDirectInitializers(in: Syntax(member.decl), into: &result)
    }
    return result
}

private func collectDirectInitializers(
    in syntax: Syntax,
    into result: inout [InitializerDeclSyntax]
) {
    if let initializer = syntax.as(InitializerDeclSyntax.self) {
        result.append(initializer)
        return
    }

    guard syntax.is(IfConfigDeclSyntax.self)
        || syntax.is(IfConfigClauseListSyntax.self)
        || syntax.is(IfConfigClauseSyntax.self)
        || syntax.is(MemberBlockItemSyntax.self)
        || syntax.is(MemberBlockItemListSyntax.self) else {
        return
    }
    for child in syntax.children(viewMode: .sourceAccurate) {
        collectDirectInitializers(in: child, into: &result)
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

private func diagnoseInvalidContainerBoolArguments(
    options: DIContainerAttributeInfo,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> Bool {
    guard let attribute = InnoDICore.findInnoDIAttribute(named: "DIContainer", in: declaration.attributes) else {
        return false
    }

    let states: [(label: String, state: BoolArgumentParseState)] = [
        ("root", options.rootParseState),
        ("validateDAG", options.validateDAGParseState),
        ("mainActor", options.mainActorParseState)
    ]
    var hadErrors = false
    for item in states where item.state.isInvalid {
        context.diagnose(
            Diagnostic(
                node: extractArgumentExpression(label: item.label, from: attribute).map(Syntax.init) ?? Syntax(attribute),
                message: SimpleDiagnostic.containerBoolLiteralRequired(label: item.label)
            )
        )
        hadErrors = true
    }
    return hadErrors
}

func extractWithDependencyReferences(
    from attribute: AttributeSyntax,
    requiringCanonicalProvidePath: Bool = false
) -> [WithDependencyReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments {
        guard let label = argument.label?.text else { continue }
        switch label {
        case "with":
            guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else { continue }
            return arrayExpr.elements.compactMap { element in
                guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                      !requiringCanonicalProvidePath
                        || (
                            keyPath.root?.trimmedDescription == "Self"
                                && keyPath.components.count == 1
                        ),
                      let property = keyPath.components.last?
                        .component.as(KeyPathPropertyComponentSyntax.self)?
                        .declName.baseName.text else {
                    return nil
                }
                return WithDependencyReference(
                    name: property,
                    anchorExpression: ExprSyntax(keyPath)
                )
            }
        default:
            continue
        }
    }

    return []
}

private func sameNameWiringExpressionSyntax(
    for state: SubContainerSameNameWiringParseState,
    in attribute: AttributeSyntax
) -> ExprSyntax? {
    switch state {
    case .omitted:
        return nil
    case let .parsed(label, _), let .invalid(label):
        return extractArgumentExpression(label: label.rawValue, from: attribute)
    }
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

private func extractInvalidSubContainerBindingReferences(from attribute: AttributeSyntax) -> [InvalidSubContainerBindingReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "bindings" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return [
                InvalidSubContainerBindingReference(anchorExpression: argument.expression)
            ]
        }

        var invalidReferences: [InvalidSubContainerBindingReference] = []
        for element in arrayExpr.elements {
            guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                invalidReferences.append(
                    InvalidSubContainerBindingReference(anchorExpression: element.expression)
                )
                continue
            }

            var hasChild = false
            var hasParent = false
            var elementIsInvalid = false

            for tupleElement in tupleExpr.elements {
                guard let label = tupleElement.label?.text else { continue }
                switch label {
                case "child", "parent":
                    guard finalKeyPathExpression(tupleElement.expression) != nil else {
                        elementIsInvalid = true
                        continue
                    }
                    if label == "child" {
                        hasChild = true
                    } else {
                        hasParent = true
                    }
                default:
                    continue
                }
            }

            if elementIsInvalid || !hasChild || !hasParent {
                invalidReferences.append(
                    InvalidSubContainerBindingReference(anchorExpression: element.expression)
                )
            }
        }
        return invalidReferences
    }

    return []
}

private struct FeatureRootParseResult {
    let roots: [FeatureRootMemberModel]
    let hadErrors: Bool
}

private struct ParsedFeatureRootArgument {
    let root: FeatureRootMemberModel?
    let invalidAliasText: String?
    let aliasAnchor: Syntax?
    let invalidRootAnchor: Syntax?
}

private func extractFeatureRootReferences(
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
                let parsed = parseFeatureRootInitializer(element.expression, propertyName: propertyName)
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
                            message: SimpleDiagnostic.swiftUIFeatureRootInvalidAlias(alias: invalidAliasText)
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
                    message: SimpleDiagnostic.swiftUIFeatureRootDuplicateDefault(propertyName: propertyName)
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
                    message: SimpleDiagnostic.swiftUIFeatureRootHelperNameConflict(helperName: root.helperName)
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
                    message: SimpleDiagnostic.swiftUIFeatureRootHelperNameConflict(helperName: root.helperName)
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
                if let value = stringLiteralValue(argument.expression), isValidFeatureRootAlias(value) {
                    alias = value
                } else {
                    invalidAliasText = stringLiteralValue(argument.expression) ?? argument.expression.trimmedDescription
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

private func finalKeyPathExpression(_ expression: ExprSyntax) -> KeyPathExprSyntax? {
    guard let keyPath = expression.as(KeyPathExprSyntax.self),
          keyPath.components.last?
            .component.as(KeyPathPropertyComponentSyntax.self)?
            .declName.baseName.text != nil else {
        return nil
    }
    return keyPath
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

internal func detectConflictingGlobalActor(in attributes: AttributeListSyntax?) -> String? {
    guard let attributes else { return nil }
    for attribute in attributes {
        guard let attr = attribute.as(AttributeSyntax.self) else { continue }
        guard let attributeName = globalActorAttributeName(from: attr.attributeName) else { continue }
        if attributeName.terminalName == "DIContainer"
            || isStandardMainActorAttributeName(attr.attributeName) {
            continue
        }
        if attributeName.terminalName.hasSuffix("Actor") {
            return attributeName.sourceSpelling
        }
    }
    return nil
}

internal func findStandardMainActorAttribute(
    in attributes: AttributeListSyntax?
) -> AttributeSyntax? {
    guard let attributes else { return nil }
    return attributes.compactMap { $0.as(AttributeSyntax.self) }.first {
        isStandardMainActorAttributeName($0.attributeName)
    }
}

private func isStandardMainActorAttributeName(_ attributeName: TypeSyntax) -> Bool {
    switch attributeName.trimmedDescription {
    case "MainActor", "Swift.MainActor", "_Concurrency.MainActor":
        return true
    default:
        return false
    }
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
