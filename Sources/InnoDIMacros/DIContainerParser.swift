import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

private enum DIContainerMemberParseResult<Value> {
    case success(Value)
    case failure
}

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
        var hadErrors = diagnoseContainerPreflight(
            options: options,
            declaration: decl,
            context: context
        )

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

            let managedSemantics = parseManagedMemberSemantics(
                varDecl.attributes
            )
            let provideAttributes = managedSemantics.provideAttributes
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
            let subContainerAttributes = managedSemantics.subContainerAttributes
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
                    context.emit(
                        SimpleDiagnostic.containerMainActorConflict(
                            actorName: conflictingActor
                        ),
                        at: Syntax(varDecl)
                    )
                    hadErrors = true
                    continue
                }

                if varDecl.modifiers.contains(where: { $0.name.text == "nonisolated" }) {
                    let memberName = varDecl.bindings.first?
                        .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                        ?? "<unknown>"
                    context.emit(
                        SimpleDiagnostic.containerMainActorNonisolatedMember(
                            memberName: memberName
                        ),
                        at: Syntax(varDecl)
                    )
                    hadErrors = true
                    continue
                }
            }

            if let subAttribute = subContainerAttribute, provideAttribute != nil {
                let memberName = varDecl.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                    ?? "<unknown>"
                context.emit(
                    SimpleDiagnostic.subConflictsWithProvide(memberName: memberName),
                    at: Syntax(subAttribute)
                )
                hadErrors = true
                continue
            }

            if let subAttribute = subContainerAttribute {
                switch parseSubContainerMember(
                    variable: varDecl,
                    attribute: subAttribute,
                    semantics: managedSemantics,
                    sourceOrder: sourceOrder,
                    existingSubContainers: subContainerMembers,
                    declaration: decl,
                    firstIdentifierByName: &firstManagedIdentifierByName,
                    context: context
                ) {
                case .success(let member):
                    subContainerMembers.append(member)
                case .failure:
                    hadErrors = true
                }
                continue
            }

            guard let attribute = provideAttribute else {
                continue
            }

            switch parseProvideMember(
                variable: varDecl,
                attribute: attribute,
                semantics: managedSemantics,
                sourceOrder: sourceOrder,
                firstIdentifierByName: &firstManagedIdentifierByName,
                context: context
            ) {
            case .success(let member):
                members.append(member)
            case .failure:
                hadErrors = true
            }
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

    // MARK: - Container preflight

    private static func diagnoseContainerPreflight(
        options: DIContainerAttributeInfo,
        declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = diagnoseInvalidContainerBoolArguments(
            options: options,
            declaration: declaration,
            context: context
        )

        if options.mainActor,
           let conflictingActor = detectConflictingGlobalActor(
            in: declaration.attributes
           ) {
            context.emit(
                SimpleDiagnostic.containerMainActorConflict(
                    actorName: conflictingActor
                ),
                at: Syntax(declaration)
            )
            hadErrors = true
        }

        for member in unmanagedStoredContainerMembers(in: declaration) {
            context.emit(
                SimpleDiagnostic.containerUnmanagedStoredProperty(
                    memberName: member.name
                ),
                at: member.anchor
            )
            hadErrors = true
        }

        for conditionalMember in conditionallyCompiledProvideMembers(
            in: declaration
        ) {
            let memberName = conditionalMember.declaration.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                ?? "<unknown>"
            context.emit(
                SimpleDiagnostic.provideConditionalDeclarationUnsupported(
                    memberName: memberName
                ),
                at: Syntax(conditionalMember.attribute)
            )
            hadErrors = true
        }

        for conditionalMember in conditionallyCompiledSubContainerMembers(
            in: declaration
        ) {
            let memberName = conditionalMember.declaration.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                ?? "<unknown>"
            context.emit(
                SimpleDiagnostic.subConditionalDeclarationUnsupported(
                    memberName: memberName
                ),
                at: Syntax(conditionalMember.attribute)
            )
            hadErrors = true
        }
        return hadErrors
    }

    // MARK: - SubContainer member parsing

    private static func parseSubContainerMember(
        variable: VariableDeclSyntax,
        attribute: AttributeSyntax,
        semantics: ManagedMemberSemantics,
        sourceOrder: Int,
        existingSubContainers: [SubContainerMemberModel],
        declaration: some DeclGroupSyntax,
        firstIdentifierByName: inout [String: TokenSyntax],
        context: some MacroExpansionContext
    ) -> DIContainerMemberParseResult<SubContainerMemberModel> {
        guard let validatedBinding = validateBindingForAttribute(
            variable,
            kind: .subContainer,
            context: context
        ) else {
            return .failure
        }
        if isEscapedInnoDIIdentifier(
            validatedBinding.identifier.identifier
        ) {
            // Public @SubContainer owns the single escaped-name diagnostic.
            // Hidden child support is never attached.
            return .failure
        }
        guard isSupportedSubContainerStoredProperty(variable) else {
            context.emit(
                SimpleDiagnostic.subRequiresDirectContainerMember(
                    memberName: validatedBinding.identifier.identifier.text
                ),
                at: Syntax(attribute)
            )
            // Fail before hidden child support or generated init code can
            // reference peers that the declaration cannot safely own.
            return .failure
        }
        guard let arguments = semantics.subContainerArguments else {
            return .failure
        }

        let memberName = validatedBinding.identifier.identifier.text
        if diagnoseDuplicateManagedMemberName(
            memberName,
            identifier: validatedBinding.identifier.identifier,
            firstIdentifierByName: &firstIdentifierByName,
            context: context
        ) {
            return .failure
        }
        let featureRoots = extractFeatureRootReferences(
            from: attribute,
            propertyName: memberName,
            existingSubContainers: existingSubContainers,
            declaration: declaration,
            context: context
        )
        guard !featureRoots.hadErrors else {
            return .failure
        }

        return .success(
            SubContainerMemberModel(
                sourceOrder: sourceOrder,
                name: memberName,
                type: validatedBinding.typeAnnotation.type,
                scope: arguments.scope,
                scopeName: arguments.scopeName,
                scopeExpressionSyntax: extractArgumentExpression(
                    label: "scope",
                    from: attribute
                ),
                parentDependencies: arguments.dependencies,
                hasWithDependencies: arguments.hasWithDependencies,
                sameNameWiring: arguments.sameNameWiring,
                sameNameWiringExpressionSyntax: sameNameWiringExpressionSyntax(
                    for: arguments.sameNameWiring,
                    in: attribute
                ),
                explicitBindings: extractSubContainerBindingReferences(
                    from: attribute
                ),
                invalidBindingReferences:
                    extractInvalidSubContainerBindingReferences(
                        from: attribute
                    ),
                bindingsParseState: arguments.bindingsParseState,
                parentDependencyReferences: extractWithDependencyReferences(
                    from: attribute
                ),
                featureRoots: featureRoots.roots,
                attribute: attribute,
                bindingSyntax: validatedBinding.binding
            )
        )
    }

    // MARK: - Provide member parsing

    private static func parseProvideMember(
        variable: VariableDeclSyntax,
        attribute: AttributeSyntax,
        semantics: ManagedMemberSemantics,
        sourceOrder: Int,
        firstIdentifierByName: inout [String: TokenSyntax],
        context: some MacroExpansionContext
    ) -> DIContainerMemberParseResult<ProvideMemberModel> {
        guard let validatedBinding = validateBindingForAttribute(
            variable,
            kind: .provide,
            context: context
        ) else {
            return .failure
        }

        // Public @Provide owns the declaration-shape diagnostic. Binding
        // arity/name/type remains first so its more precise diagnostics stay
        // reachable without attaching an accessor to unsafe syntax.
        guard isSupportedProvideStoredProperty(variable),
              !isEscapedInnoDIIdentifier(
                validatedBinding.identifier.identifier
              ) else {
            return .failure
        }

        let memberName = validatedBinding.identifier.identifier.text
        if diagnoseDuplicateManagedMemberName(
            memberName,
            identifier: validatedBinding.identifier.identifier,
            firstIdentifierByName: &firstIdentifierByName,
            context: context
        ) {
            return .failure
        }
        guard let arguments = semantics.provideArguments else {
            return .failure
        }

        var hadArgumentErrors = false
        if arguments.escapingParseState.isInvalid {
            context.emit(
                SimpleDiagnostic.provideBoolLiteralRequired(
                    label: "escaping"
                ),
                at: extractArgumentExpression(
                    label: "escaping",
                    from: attribute
                ).map(Syntax.init) ?? Syntax(attribute)
            )
            hadArgumentErrors = true
        }
        if arguments.dependenciesParseState.isInvalid {
            context.emit(
                SimpleDiagnostic.provideInvalidWithDependencies(
                    memberName: memberName,
                    expectedRoot: "Self"
                ),
                at: extractArgumentExpression(
                    label: "with",
                    from: attribute
                ).map(Syntax.init) ?? Syntax(attribute)
            )
            hadArgumentErrors = true
        }
        guard !hadArgumentErrors,
              let scope = arguments.scope else {
            // ProvideMacro owns the terminal unknown-scope diagnostic; this
            // parser only fails closed so invalid members cannot reach codegen.
            return .failure
        }

        let closureParameters: ClosureParameterList
        if let closure = arguments.factoryExpr?.as(ClosureExprSyntax.self) {
            closureParameters = parseClosureParameterNames(closure)
        } else if let closure = arguments.asyncFactoryExpr?.as(
            ClosureExprSyntax.self
        ) {
            closureParameters = parseClosureParameterNames(closure)
        } else {
            closureParameters = ClosureParameterList(
                names: [],
                references: [],
                hasWildcard: false
            )
        }

        return .success(
            ProvideMemberModel(
                sourceOrder: sourceOrder,
                name: memberName,
                type: validatedBinding.typeAnnotation.type,
                scope: scope,
                factory: arguments.factoryExpr,
                asyncFactory: arguments.asyncFactoryExpr,
                asyncFactoryIsThrowing: arguments.asyncFactoryIsThrowing,
                typeExpr: arguments.typeExpr,
                initializer: validatedBinding.binding.initializer?.value,
                escapingInput: arguments.escaping,
                escapingParseState: arguments.escapingParseState,
                withDependencies: arguments.dependencies,
                withDependenciesParseState: arguments.dependenciesParseState,
                withDependencyReferences: extractWithDependencyReferences(
                    from: attribute,
                    requiringCanonicalProvidePath: true
                ),
                closureDependencies: closureParameters.names,
                closureParameterReferences: closureParameters.references,
                closureHasWildcard: closureParameters.hasWildcard,
                attribute: attribute,
                bindingSyntax: validatedBinding.binding
            )
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

    context.emit(
        SimpleDiagnostic.containerDuplicateMemberName(
            memberName: memberName
        ),
        at: Syntax(identifier),
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
        context.emit(
            kind.singleBindingDiagnostic,
            at: Syntax(varDecl)
        )
        return nil
    }

    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
        context.emit(
            kind.namedPropertyDiagnostic,
            at: Syntax(binding.pattern)
        )
        return nil
    }

    guard let typeAnnotation = binding.typeAnnotation else {
        context.emit(
            kind.explicitTypeDiagnostic,
            at: Syntax(binding.pattern)
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

func extractArgumentExpression(label: String, from attribute: AttributeSyntax) -> ExprSyntax? {
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
        context.emit(
            SimpleDiagnostic.containerBoolLiteralRequired(label: item.label),
            at: extractArgumentExpression(label: item.label, from: attribute).map(Syntax.init) ?? Syntax(attribute)
        )
        hadErrors = true
    }
    return hadErrors
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
