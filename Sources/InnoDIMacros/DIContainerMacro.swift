import InnoDICore
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct DIContainerMacro: MemberMacro {
    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: attribute, providingMembersOf: decl, in: context)
    }

    public static func expansion(
        of attribute: AttributeSyntax,
        providingMembersOf decl: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let declarationSupport = classifyDIContainerDeclaration(
            decl,
            lexicalContext: context.lexicalContext
        )
        guard declarationSupport.isSupported else {
            declarationSupport.diagnose(
                at: attribute,
                declaration: decl,
                in: context
            )
            return []
        }

        let userDefinedInitializers = DIContainerParser.userDefinedInitializers(in: decl)
        if !userDefinedInitializers.isEmpty {
            for initializer in userDefinedInitializers {
                context.emit(
                    SimpleDiagnostic.containerCustomInitUnsupported(),
                    at: Syntax(initializer),
                    notes: [
                        Note(
                            node: Syntax(attribute),
                            message: SimpleNote(
                                "The synthesized container initializer already covers @Input members and optional dependency overrides.",
                                code: .containerCustomInitUnsupported,
                                suffix: "synthesized-init"
                            )
                        ),
                        Note(
                            node: Syntax(initializer),
                            message: SimpleNote(
                                "Remove this custom initializer, or remove @DIContainer and wire the container manually.",
                                code: .containerCustomInitUnsupported,
                                suffix: "manual-wiring"
                            )
                        )
                    ]
                )
            }
            return []
        }

        guard let model = DIContainerParser.parse(declaration: decl, context: context) else {
            return []
        }

        let isValid = DIContainerValidator.validate(
            model: model,
            declaration: decl,
            context: context
        )
        if !isValid {
            return []
        }

        do {
            if let conflict = DIContainerParser.findOverridesNameConflict(in: decl) {
                context.emit(
                    SimpleDiagnostic.containerOverridesNameConflict(kind: conflict.kind),
                    at: Syntax(conflict.node)
                )
                return [
                    try DIContainerCodeGenerator.generateInit(for: model),
                    makeOverridesConflictMountTypeDecl(model: model),
                    makeOverridesConflictRecoveryInitDecl(model: model),
                ]
            }

            var generated = try DIContainerCodeGenerator.generateAll(
                for: model,
                prependingInitializationMARK: !hasHierarchyAttribute(
                    named: "DIComponent",
                    in: decl.attributes
                ) && model.options.role != .component
            )
            if model.options.role == .component,
               !hasHierarchyAttribute(named: "DIComponent", in: decl.attributes) {
                generated.append(contentsOf: try DIComponentMacro.expansion(
                    of: attribute,
                    providingMembersOf: decl,
                    in: context
                ))
            }
            return generated
        } catch let error as CodegenInvariantError {
            context.emit(
                SimpleDiagnostic.internalCodegenInvariant(description: error.description),
                at: Syntax(attribute)
            )
            return []
        }
    }
}

extension DIContainerMacro: MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        guard let options = parseDIContainerAttribute(declaration.attributes),
              classifyDIContainerDeclaration(
                declaration,
                lexicalContext: context.lexicalContext
              ).isSupported else {
            return []
        }

        if let factory = member.as(StructDeclSyntax.self),
           factory.name.text == "AssistedFactory",
           findInnoDIAttribute(
               named: "AssistedFactory",
               in: factory.attributes
           ) != nil {
            let validationContext = DiagnosticSuppressingMacroExpansionContext(
                forwardingTo: context
            )
            guard let model = DIContainerParser.parse(
                declaration: declaration,
                context: validationContext
            ) else { return [] }
            return [
                assistedFactoryMetadataAttribute(
                    for: model,
                    isMainActor: options.mainActor
                ),
            ]
        }

        guard let variable = member.as(VariableDeclSyntax.self) else {
            return []
        }

        // Preserve the public misuse diagnostic before any container-wide
        // recovery suppression. A forged support accessor must never become
        // silent just because another direct declaration also uses a reserved
        // generated name.
        if let manuallyAttachedAccessor = findInnoDIAttribute(
            named: "_InnoDIProvideAccessor",
            in: variable.attributes
        ) {
            let memberName = variable.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                ?? "<unknown>"
            context.emit(
                SimpleDiagnostic.provideGeneratedAccessorManualAttachment(
                    memberName: memberName
                ),
                at: Syntax(manuallyAttachedAccessor)
            )
            return []
        }

        if let manuallyAttachedAccessor = findInnoDIAttribute(
            named: "_InnoDISubContainerAccessor",
            in: variable.attributes
        ) {
            let memberName = variable.bindings.first?
                .pattern.as(IdentifierPatternSyntax.self)?.identifier.text
                ?? "<unknown>"
            context.emit(
                SimpleDiagnostic.subGeneratedAccessorManualAttachment(
                    memberName: memberName
                ),
                at: Syntax(manuallyAttachedAccessor)
            )
            return []
        }

        // A source-written initializer owns initialization of the original
        // stored properties. The container member role emits the terminal
        // custom-init diagnostic; attaching a generated accessor here would
        // turn those properties into get-only computed members and make valid
        // `self.member = value` assignments produce secondary Swift errors.
        guard DIContainerParser.userDefinedInitializers(
            in: declaration
        ).isEmpty else {
            return []
        }

        // The container member expansion owns the stable reserved-name
        // diagnostics. Do not emit actor/accessor support through a qualifier
        // that a direct declaration has already shadowed.
        guard !containerHasReservedGeneratedName(
            in: declaration,
            lexicalContext: context.lexicalContext
        ) else {
            return []
        }
        let provideAttributes = InnoDICore.findManagedProviderAttributes(
            in: variable.attributes
        )
        let subContainerAttributes = findInnoDIAttributes(
            named: "SubContainer",
            in: variable.attributes
        )
        let hasProvide = !provideAttributes.isEmpty
        let hasSubContainer = !subContainerAttributes.isEmpty
        let isInstanceMember = !variable.modifiers.contains {
            $0.name.text == "static" || $0.name.text == "class"
        }

        if isConditionallyCompiledSubContainerMember(variable, in: declaration) {
            // The public peer and container parser own the diagnostic. Keep
            // the declaration stored and emit no partial child support.
            return []
        }

        if isConditionallyCompiledProvideMember(variable, in: declaration) {
            // The container member expansion diagnoses this unsupported shape.
            // Attach only a recovery accessor so the rejected stored property
            // cannot create a synthesized-init or missing-storage cascade.
            if isInstanceMember,
               hasProvide,
               !hasSubContainer,
               canAttachGeneratedProvideAccessor(to: variable) {
                return [provideAccessorAttribute(recovery: true)]
            }
            return []
        }

        var attributes: [AttributeSyntax] = []
        // Property-level isolation is required for call-site enforcement.
        // Accessor-level `@MainActor` checks the generated getter body but does
        // not prevent another actor from reading the property synchronously.
        // This phase sees the source declaration before generated attributes,
        // so source-written actor/property-wrapper attributes are still
        // rejected by the closed declaration-shape validation below.
        let isContainerManagedMember = hasProvide || hasSubContainer

        if options.mainActor,
           isInstanceMember,
           isContainerManagedMember,
           findStandardMainActorAttribute(in: variable.attributes) == nil,
           detectConflictingGlobalActor(in: variable.attributes) == nil,
           !variable.modifiers.contains(where: { $0.name.text == "nonisolated" }) {
            attributes.append(mainActorAttribute())
        }

        let shouldAttachProvideAccessor = hasProvide
            && !hasSubContainer
            && provideAttributes.count == 1
            && isInstanceMember
            && canAttachGeneratedProvideAccessor(to: variable)
        let shouldAttachSubContainerAccessor = hasSubContainer
            && subContainerAttributes.count == 1
            && isInstanceMember
            && canAttachGeneratedSubContainerAccessor(to: variable)
        let hasGeneratedPeerCollision =
            (shouldAttachProvideAccessor || shouldAttachSubContainerAccessor)
            && hasGeneratedPeerSymbolCollision(in: declaration)

        if shouldAttachProvideAccessor {
            let recovery = hasGeneratedPeerCollision
                || provideMemberValidationRecovery(
                    member: variable,
                    in: declaration,
                    options: options
                )
            attributes.append(provideAccessorAttribute(recovery: recovery))
        }

        if shouldAttachSubContainerAccessor {
            let recovery = hasGeneratedPeerCollision
                || hasProvide
                || subContainerMemberValidationRecovery(
                    member: variable,
                    in: declaration,
                    context: context,
                    options: options
                )
            attributes.append(
                subContainerAccessorAttribute(recovery: recovery)
            )
        }

        return attributes
    }
}

private func canAttachGeneratedSubContainerAccessor(
    to declaration: VariableDeclSyntax
) -> Bool {
    InnoDICore.canAttachGeneratedSubContainerAccessor(to: declaration)
}

private func subContainerMemberValidationRecovery(
    member: VariableDeclSyntax,
    in declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext,
    options: DIContainerAttributeInfo
) -> Bool {
    guard let attribute = findInnoDIAttribute(
        named: "SubContainer",
        in: member.attributes
    ) else {
        return true
    }
    let arguments = parseSubContainerArguments(attribute)
    if !InnoDICore.isLocallyValidSubContainerConfiguration(arguments) {
        return true
    }
    if options.mainActor,
       (detectConflictingGlobalActor(in: member.attributes) != nil
        || member.modifiers.contains(where: { $0.name.text == "nonisolated" })) {
        return true
    }
    if !DIContainerParser.userDefinedInitializers(in: declaration).isEmpty {
        return true
    }

    // The hidden accessor owns every concrete child-storage peer. Mirror the
    // complete container validation gate without re-emitting its diagnostics:
    // if the member role allowed `recovery: false` after a graph or wiring
    // error, those peers could survive even
    // though the container member role correctly suppressed all public code.
    let validationContext = DiagnosticSuppressingMacroExpansionContext(
        forwardingTo: context
    )
    guard let model = DIContainerParser.parse(
        declaration: declaration,
        context: validationContext
    ) else {
        return true
    }
    guard DIContainerValidator.validate(
        model: model,
        declaration: declaration,
        context: validationContext
    ) else {
        return true
    }

    do {
        if DIContainerParser.findOverridesNameConflict(in: declaration) != nil {
            _ = try DIContainerCodeGenerator.generateInit(for: model)
        } else {
            _ = try DIContainerCodeGenerator.generateAll(for: model)
        }
        return false
    } catch is CodegenInvariantError {
        return true
    } catch {
        return true
    }
}

private struct DIContainerMemberConstructionSummary {
    let scope: ProvideScope
    let effect: ProvideConstructionEffect
    let writtenType: String
}

/// Member-attribute expansion is the one attached-macro phase guaranteed to
/// receive both the direct member and its container's complete sibling list.
/// Attach the accessor owner here so normal generation and invalid-edge
/// recovery both use the same compiler-visible macro expansion path.
private func provideMemberValidationRecovery(
    member: VariableDeclSyntax,
    in declaration: some DeclGroupSyntax,
    options: DIContainerAttributeInfo
) -> Bool {
    if !unmanagedStoredContainerMembers(in: declaration).isEmpty {
        return true
    }

    guard let attribute = InnoDICore.findManagedProviderAttribute(in: member.attributes) else {
        return true
    }

    if hasDuplicateManagedMemberName(
        member,
        in: declaration,
        options: options
    ) {
        return true
    }

    let arguments = parseProvideArguments(attribute)
    if !isLocallyValidProvideConfiguration(
        declaration: member,
        arguments: arguments
    ) || findInnoDIAttribute(named: "SubContainer", in: member.attributes) != nil {
        return true
    }

    if options.mainActor,
       detectConflictingGlobalActor(in: member.attributes) != nil
        || member.modifiers.contains(where: { $0.name.text == "nonisolated" }) {
        return true
    }

    switch arguments.constructionEffect {
    case .synchronous:
        break
    case .asynchronous, .asynchronousThrowing:
        if let memberName = member.bindings.first?
            .pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
            hasIncomingProvideWithReference(
                to: memberName,
                in: declaration
            ) {
            // Swift rejects key paths to async/throwing properties before the
            // consumer macro can recover. Make the invalid target accessor
            // synchronous too; the dedicated InnoDI diagnostic remains terminal.
            return true
        }
    }

    guard arguments.scope == .transient else { return false }

    var providers: [String: DIContainerMemberConstructionSummary] = [:]
    for sibling in declaration.memberBlock.members {
        guard let variable = sibling.decl.as(VariableDeclSyntax.self),
              canAttachGeneratedProvideAccessor(to: variable),
              let providerAttribute = InnoDICore.findManagedProviderAttribute(in: variable.attributes),
              findInnoDIAttribute(named: "SubContainer", in: variable.attributes) == nil,
              !options.mainActor
                || (
                    detectConflictingGlobalActor(in: variable.attributes) == nil
                    && !variable.modifiers.contains(where: { $0.name.text == "nonisolated" })
                ),
              let providerBinding = variable.bindings.first,
              let identifier = providerBinding.pattern.as(IdentifierPatternSyntax.self) else {
            continue
        }
        let providerArguments = parseProvideArguments(providerAttribute)
        guard isLocallyValidProvideConfiguration(
            declaration: variable,
            arguments: providerArguments
        ), let providerScope = providerArguments.scope else {
            continue
        }
        providers[identifier.identifier.text] = DIContainerMemberConstructionSummary(
            scope: providerScope,
            effect: providerArguments.constructionEffect,
            writtenType: providerBinding.typeAnnotation?.type
                .trimmedDescription ?? ""
        )
    }

    if arguments.isMultibinding {
        guard let collectionType = member.bindings.first?.typeAnnotation?.type,
              multibindingElementType(collectionType) != nil else {
            return true
        }
        return arguments.dependencies.contains { dependencyName in
            guard let provider = providers[dependencyName],
                  dependencyName != member.bindings.first?
                    .pattern.as(IdentifierPatternSyntax.self)?
                    .identifier.text else {
                return true
            }
            if case .synchronous = provider.effect { return false }
            return true
        }
    }

    let closure: ClosureExprSyntax?
    if let factory = arguments.factoryExpr?.as(ClosureExprSyntax.self) {
        closure = factory
    } else {
        closure = arguments.asyncFactoryExpr?.as(ClosureExprSyntax.self)
    }

    if let closure {
        let parsedClosure = parseClosureParameterNames(closure)
        if parsedClosure.hasWildcard {
            return true
        }
        if transientClosureNeedsValidationRecovery(
            references: parsedClosure.references,
            consumerEffect: arguments.constructionEffect,
            providers: providers
        ) {
            return true
        }
    }

    if arguments.dependencies.contains(where: { providers[$0] == nil }) {
        return true
    }

    if arguments.dependencies.contains(where: { dependencyName in
        guard let provider = providers[dependencyName] else { return false }
        return dependencyEffectMismatch(
            consumer: arguments.constructionEffect,
            provider: provider.effect
        ) != nil
    }) {
        return true
    }

    return false
}

private func hasIncomingProvideWithReference(
    to memberName: String,
    in declaration: some DeclGroupSyntax
) -> Bool {
    declaration.memberBlock.members.contains { sibling in
        guard let variable = sibling.decl.as(VariableDeclSyntax.self),
              let attribute = InnoDICore.findManagedProviderAttribute(
                in: variable.attributes
              ) else {
            return false
        }
        return extractWithDependencyReferences(
            from: attribute,
            requiringCanonicalProvidePath: true
        ).contains {
            $0.name == memberName
        }
    }
}

private func transientClosureNeedsValidationRecovery(
    references: [ClosureParameterReference],
    consumerEffect: ProvideConstructionEffect,
    providers: [String: DIContainerMemberConstructionSummary]
) -> Bool {
    references.contains { reference in
        guard let provider = providers[reference.name] else { return true }

        switch reference.kind {
        case .hard:
            return dependencyEffectMismatch(
                consumer: consumerEffect,
                provider: provider.effect
            ) != nil
        case .soft:
            if case .synchronous = provider.effect { return false }
            return true
        case .provider:
            guard provider.scope == .transient else { return true }
            if case .synchronous = provider.effect { return false }
            return true
        }
    }
}

private func provideAccessorAttribute(recovery: Bool) -> AttributeSyntax {
    let attribute: AttributeSyntax = recovery
        ? "@InnoDI._InnoDIProvideAccessor(recovery: true)"
        : "@InnoDI._InnoDIProvideAccessor(recovery: false)"
    return attribute
}

private func subContainerAccessorAttribute(recovery: Bool) -> AttributeSyntax {
    let attribute: AttributeSyntax = recovery
        ? "@InnoDI._InnoDISubContainerAccessor(recovery: true)"
        : "@InnoDI._InnoDISubContainerAccessor(recovery: false)"
    return attribute
}

private func assistedFactoryMetadataAttribute(
    for model: DIContainerExpansionModel,
    isMainActor: Bool
) -> AttributeSyntax {
    let orderedNames = model.inputMembers.map(\.name)
    let escapingNames = model.inputMembers.filter { member in
        member.escapingInput || isDirectNonOptionalFunctionType(member.type)
    }.map(\.name)
    let order = orderedNames.map { "\"\($0)\"" }.joined(separator: ", ")
    let escaping = escapingNames.map { "\"\($0)\"" }.joined(separator: ", ")
    return AttributeSyntax(
        stringLiteral: "@InnoDI._InnoDIAssistedFactoryMetadata(order: [\(order)], escaping: [\(escaping)], mainActor: \(isMainActor))"
    )
}
