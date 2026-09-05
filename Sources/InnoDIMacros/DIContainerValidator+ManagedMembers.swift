import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Managed @Provide members

extension DIContainerValidator {
    /// Runs declaration-local checks before deriving dependency diagnostics.
    /// Keeping those phases explicit prevents an invalid provider from being
    /// treated as a usable graph node by later checks.
    static func validateManagedMembers(
        model: DIContainerExpansionModel,
        resolutionContext: DependencyResolutionContext,
        memberByName: [String: ProvideMemberModel],
        dagValidationEnabled: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for (index, member) in model.members.enumerated() {
            hadErrors = validateFactoryParameterDeclarations(
                member: member,
                context: context
            ) || hadErrors

            let constructionState = ManagedMemberConstructionState(
                member: member
            )
            hadErrors = validateProviderTypeShape(
                member: member,
                context: context
            ) || hadErrors
            hadErrors = validateConstructionConfiguration(
                member: member,
                state: constructionState,
                context: context
            ) || hadErrors
            hadErrors = validateFactoryEffects(
                member: member,
                state: constructionState,
                context: context
            ) || hadErrors

            if member.isMultibinding {
                hadErrors = validateMultibinding(
                    member: member,
                    memberByName: memberByName,
                    context: context
                ) || hadErrors
                continue
            }

            // Configuration diagnostics own the declaration until its local
            // construction mode is coherent. Do not derive sibling lookup,
            // graph, or effect errors from a provider that code generation
            // has already excluded.
            guard member.hasLocallyValidConstructionConfiguration else {
                continue
            }

            let hardClosureNames = Set(member.hardClosureDependencies)
            let softClosureReferences = Dictionary(
                member.softClosureParameterReferences.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let providerClosureReferences = Dictionary(
                member.providerClosureParameterReferences.map { ($0.name, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let effectMismatchNames = diagnoseIncompatibleDependencyEffects(
                member: member,
                memberByName: memberByName,
                context: context
            )
            hadErrors = !effectMismatchNames.isEmpty || hadErrors
            hadErrors = validateDeferredEagerCalls(
                member: member,
                lazyDependencyNames: Set(softClosureReferences.keys),
                providerDependencyNames: Set(providerClosureReferences.keys),
                context: context
            ) || hadErrors
            hadErrors = validateClosureDependencies(
                member: member,
                memberIndex: index,
                resolutionContext: resolutionContext,
                memberByName: memberByName,
                hardClosureNames: hardClosureNames,
                softClosureReferences: softClosureReferences,
                providerClosureReferences: providerClosureReferences,
                effectMismatchNames: effectMismatchNames,
                dagValidationEnabled: dagValidationEnabled,
                context: context
            ) || hadErrors
            hadErrors = validateWithDependencies(
                member: member,
                memberIndex: index,
                resolutionContext: resolutionContext,
                memberByName: memberByName,
                effectMismatchNames: effectMismatchNames,
                dagValidationEnabled: dagValidationEnabled,
                context: context
            ) || hadErrors
        }
        return hadErrors
    }

    private static func validateMultibinding(
        member: ProvideMemberModel,
        memberByName: [String: ProvideMemberModel],
        context: some MacroExpansionContext
    ) -> Bool {
        guard multibindingElementType(member.type) != nil else {
            context.emit(
                SimpleDiagnostic.multibindingCollectionTypeRequired(
                    memberName: member.name
                ),
                at: Syntax(member.type)
            )
            return true
        }

        var hadErrors = false
        for contributorName in member.withDependencies {
            let anchor = member.withDependencyReferences.first {
                $0.name == contributorName
            }.map { Syntax($0.anchorExpression) } ?? Syntax(member.attribute)
            guard let contributor = memberByName[contributorName],
                  contributor.name != member.name else {
                context.emit(
                    SimpleDiagnostic.multibindingUnknownContributor(
                        memberName: member.name,
                        contributorName: contributorName
                    ),
                    at: anchor
                )
                hadErrors = true
                continue
            }
            if contributor.isAsyncFactory {
                context.emit(
                    SimpleDiagnostic.multibindingAsyncContributor(
                        memberName: member.name,
                        contributorName: contributorName
                    ),
                    at: anchor
                )
                hadErrors = true
                continue
            }
            // The generated array expression is the typed witness. Comparing
            // source spellings here rejects valid aliases and
            // concrete-to-existential conversions.
        }
        return hadErrors
    }

    /// Validates written closure-parameter identity before name resolution.
    private static func validateFactoryParameterDeclarations(
        member: ProvideMemberModel,
        context: some MacroExpansionContext
    ) -> Bool {
        let escapedFactoryParameters = member.closureParameterReferences.filter {
            isEscapedInnoDIIdentifier($0.token)
        }
        var hadErrors = false
        for reference in escapedFactoryParameters {
            context.emit(
                SimpleDiagnostic.provideEscapedFactoryParameter(
                    memberName: member.name,
                    parameterName: unescapedInnoDIIdentifierName(
                        reference.token
                    )
                ),
                at: Syntax(reference.token)
            )
            hadErrors = true
        }

        guard escapedFactoryParameters.isEmpty else {
            return hadErrors
        }
        for duplicate in duplicateClosureParameterReferences(
            in: member.closureParameterReferences
        ) {
            context.emit(
                SimpleDiagnostic.provideDuplicateFactoryParameter(
                    memberName: member.name,
                    parameterName: duplicate.duplicate.name
                ),
                at: Syntax(duplicate.duplicate.token),
                notes: [
                    Note(
                        node: Syntax(duplicate.first.token),
                        message: SimpleNote(
                            "The first factory parameter named '\(duplicate.first.name)' is declared here.",
                            code: .provideDuplicateFactoryParameter,
                            suffix: "first-declaration"
                        )
                    )
                ]
            )
            hadErrors = true
        }
        return hadErrors
    }

    /// Validates property type forms that cannot back generated storage.
    private static func validateProviderTypeShape(
        member: ProvideMemberModel,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        if isOpaqueSomeType(member.type) {
            var fixIts: [FixIt] = []
            if let someType = member.type.as(SomeOrAnyTypeSyntax.self) {
                fixIts.append(
                    makeTextReplacementFixIt(
                        replacing: someType.someOrAnySpecifier,
                        with: "any",
                        message: "Replace 'some' with 'any'",
                        code: .provideOpaqueTypeUnsupported
                    )
                )
            }
            context.emit(
                SimpleDiagnostic.provideOpaqueTypeUnsupported(
                    memberName: member.name
                ),
                at: Syntax(member.type),
                fixIts: fixIts
            )
            hadErrors = true
        }

        if isImplicitlyUnwrappedOptionalType(member.type) {
            var fixIts: [FixIt] = []
            if let iuoType = member.type.as(
                ImplicitlyUnwrappedOptionalTypeSyntax.self
            ) {
                fixIts.append(
                    makeTextReplacementFixIt(
                        replacing: iuoType.exclamationMark,
                        with: "?",
                        message: "Replace '!' with '?'",
                        code: .provideIUOTypeUnsupported
                    )
                )
            }
            context.emit(
                SimpleDiagnostic.provideIUOTypeUnsupported(
                    memberName: member.name
                ),
                at: Syntax(member.type),
                fixIts: fixIts
            )
            hadErrors = true
        }
        return hadErrors
    }

    /// Validates the selected construction source and scope-specific options.
    private static func validateConstructionConfiguration(
        member: ProvideMemberModel,
        state: ManagedMemberConstructionState,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        if member.initialization == .onDemand, member.scope != .shared {
            context.emit(
                SimpleDiagnostic.provideInitializationInvalidScope(
                    memberName: member.name
                ),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if member.initialization == .onDemand, member.asyncFactory != nil {
            context.emit(
                SimpleDiagnostic.provideOnDemandAsyncUnsupported(
                    memberName: member.name
                ),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if state.hasConstructionSourceConflict {
            let message: SimpleDiagnostic
            if state.constructionSourceCount == 2,
               member.factory != nil,
               member.asyncFactory != nil {
                message = .provideFactoryConflict()
            } else {
                message = .provideConstructionSourceConflict(
                    memberName: member.name
                )
            }
            context.emit(message, at: Syntax(member.attribute))
            hadErrors = true
        } else if member.scope != .input,
                  !member.isMultibinding,
                  member.withDependenciesParseState.hasArgument,
                  member.typeExpr == nil {
            context.emit(
                SimpleDiagnostic.provideWithRequiresTypeConstruction(
                    memberName: member.name
                ),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }

        if member.closureHasWildcard {
            context.emit(
                SimpleDiagnostic.transientFactoryUnnamedParameters(),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if member.scope == .shared && !state.hasConstructionSource {
            context.emit(
                SimpleDiagnostic.provideSharedFactoryRequired(),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if member.scope == .transient && !state.hasConstructionSource
            && !member.isMultibinding {
            context.emit(
                SimpleDiagnostic.provideTransientFactoryRequired(),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if member.scope == .input && state.hasInputConfiguration {
            context.emit(
                SimpleDiagnostic.provideInputInvalidConfiguration(),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if member.scope != .input && member.escapingInput {
            context.emit(
                SimpleDiagnostic.provideEscapingInvalidScope(
                    memberName: member.name
                ),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if member.scope == .input,
           member.escapingInput,
           !supportsExplicitEscapingInput(member.type) {
            context.emit(
                SimpleDiagnostic.provideEscapingNonFunctionType(
                    memberName: member.name
                ),
                at: Syntax(member.type)
            )
            hadErrors = true
        }
        if member.scope == .input,
           member.asyncFactory != nil,
           member.factory == nil,
           member.typeExpr == nil,
           member.initializer == nil {
            context.emit(
                SimpleDiagnostic.provideAsyncFactoryInvalidScope(),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        return hadErrors
    }

    /// Validates whether the selected factory expression matches its label.
    private static func validateFactoryEffects(
        member: ProvideMemberModel,
        state: ManagedMemberConstructionState,
        context: some MacroExpansionContext
    ) -> Bool {
        guard !state.hasConstructionSourceConflict else { return false }
        var hadErrors = false
        if let asyncFactory = member.asyncFactory,
           !isAsyncClosureExpression(asyncFactory) {
            context.emit(
                SimpleDiagnostic.provideAsyncFactoryMustBeAsync(),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if let factory = member.factory {
            if isAsyncClosureExpression(factory)
                || factoryExpressionContainsAwait(factory) {
                context.emit(
                    SimpleDiagnostic.provideFactoryMustBeSync(
                        memberName: member.name
                    ),
                    at: Syntax(factory)
                )
                hadErrors = true
            }
            if isThrowingClosureExpression(factory)
                || factoryExpressionContainsPlainTry(factory) {
                context.emit(
                    SimpleDiagnostic.provideFactoryMustNotThrow(
                        memberName: member.name
                    ),
                    at: Syntax(factory)
                )
                hadErrors = true
            }
        }
        return hadErrors
    }

    /// Rejects eager calls that would erase a deferred dependency boundary.
    private static func validateDeferredEagerCalls(
        member: ProvideMemberModel,
        lazyDependencyNames: Set<String>,
        providerDependencyNames: Set<String>,
        context: some MacroExpansionContext
    ) -> Bool {
        guard member.scope == .shared else { return false }
        let sharedClosures = [member.factory, member.asyncFactory]
            .compactMap { $0?.as(ClosureExprSyntax.self) }
        var hadErrors = false
        for closure in sharedClosures {
            for callSite in collectDirectDeferredEagerCalls(
                in: closure,
                dependencyNames: lazyDependencyNames
            ) {
                context.emit(
                    SimpleDiagnostic.provideLazyEagerCall(
                        memberName: member.name,
                        dependencyName: callSite.dependencyName
                    ),
                    at: callSite.node
                )
                hadErrors = true
            }
        }
        for closure in sharedClosures {
            for callSite in collectDirectDeferredEagerCalls(
                in: closure,
                dependencyNames: providerDependencyNames
            ) {
                context.emit(
                    SimpleDiagnostic.provideProviderEagerCall(
                        memberName: member.name,
                        dependencyName: callSite.dependencyName
                    ),
                    at: callSite.node
                )
                hadErrors = true
            }
        }
        return hadErrors
    }

    /// Resolves closure-parameter dependencies and enforces deferred targets.
    private static func validateClosureDependencies(
        member: ProvideMemberModel,
        memberIndex: Int,
        resolutionContext: DependencyResolutionContext,
        memberByName: [String: ProvideMemberModel],
        hardClosureNames: Set<String>,
        softClosureReferences: [String: ClosureParameterReference],
        providerClosureReferences: [String: ClosureParameterReference],
        effectMismatchNames: Set<String>,
        dagValidationEnabled: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for dependency in deduplicateStrings(member.closureDependencies) {
            let referencedMember = memberByName[dependency]
            if let referencedMember,
               !referencedMember.hasLocallyValidConstructionConfiguration {
                continue
            }
            if let softReference = softClosureReferences[dependency],
               let referencedMember,
               !referencedMember.supportsLazySoftTarget {
                context.emit(
                    SimpleDiagnostic.provideLazyUnsupportedTarget(
                        memberName: member.name,
                        dependencyName: dependency
                    ),
                    at: Syntax(softReference.token)
                )
                hadErrors = true
                continue
            }
            if let providerReference = providerClosureReferences[dependency],
               let referencedMember,
               referencedMember.scope != .transient {
                context.emit(
                    SimpleDiagnostic.provideProviderNonTransientTarget(
                        memberName: member.name,
                        dependencyName: dependency,
                        targetScope: referencedMember.scope
                    ),
                    at: Syntax(providerReference.token)
                )
                hadErrors = true
                continue
            }
            if let providerReference = providerClosureReferences[dependency],
               let referencedMember,
               referencedMember.scope == .transient,
               referencedMember.isAsyncFactory {
                context.emit(
                    SimpleDiagnostic.provideProviderUnsupportedTarget(
                        memberName: member.name,
                        dependencyName: dependency
                    ),
                    at: Syntax(providerReference.token)
                )
                hadErrors = true
                continue
            }
            if effectMismatchNames.contains(dependency) {
                continue
            }

            switch resolutionContext.status(
                of: dependency,
                forMemberAt: memberIndex
            ) {
            case .available:
                break
            case .unknown:
                if dagValidationEnabled || member.scope == .transient {
                    context.diagnose(
                        makeUnresolvedFactoryParameterDiagnostic(
                            member: member,
                            dependencyName: dependency,
                            resolutionContext: resolutionContext,
                            memberIndex: memberIndex
                        )
                    )
                    hadErrors = true
                }
            case .unavailable:
                guard dagValidationEnabled else { continue }
                // Lazy and Provider edges escape declaration-order checks;
                // only hard edges must already be available.
                if hardClosureNames.contains(dependency) {
                    context.diagnose(
                        makeUnavailableDependencyDiagnostic(
                            member: member,
                            dependencyName: dependency,
                            referencedMember: referencedMember
                        )
                    )
                    hadErrors = true
                }
            }
        }
        return hadErrors
    }

    /// Resolves explicit `with:` dependencies after effect validation.
    private static func validateWithDependencies(
        member: ProvideMemberModel,
        memberIndex: Int,
        resolutionContext: DependencyResolutionContext,
        memberByName: [String: ProvideMemberModel],
        effectMismatchNames: Set<String>,
        dagValidationEnabled: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for dependency in deduplicateStrings(member.withDependencies) {
            if effectMismatchNames.contains(dependency) {
                continue
            }
            let referencedMember = memberByName[dependency]
            if let referencedMember,
               !referencedMember.hasLocallyValidConstructionConfiguration {
                continue
            }
            guard dagValidationEnabled || member.scope == .transient else {
                continue
            }
            switch resolutionContext.status(
                of: dependency,
                forMemberAt: memberIndex
            ) {
            case .available:
                break
            case .unknown:
                context.diagnose(
                    makeUnresolvedWithDependencyDiagnostic(
                        member: member,
                        dependencyName: dependency,
                        resolutionContext: resolutionContext,
                        memberIndex: memberIndex
                    )
                )
                hadErrors = true
            case .unavailable:
                guard dagValidationEnabled else { continue }
                context.diagnose(
                    makeUnavailableDependencyDiagnostic(
                        member: member,
                        dependencyName: dependency,
                        referencedMember: referencedMember
                    )
                )
                hadErrors = true
            }
        }
        return hadErrors
    }
}

/// Derived once per member so configuration helpers share one definition of
/// what counts as a construction source.
private struct ManagedMemberConstructionState {
    let constructionSourceCount: Int
    let hasConstructionSource: Bool
    let hasInputConfiguration: Bool
    let hasConstructionSourceConflict: Bool

    init(member: ProvideMemberModel) {
        constructionSourceCount = [
            member.factory != nil,
            member.asyncFactory != nil,
            member.typeExpr != nil,
            member.initializer != nil,
        ].filter { $0 }.count
        hasConstructionSource = constructionSourceCount > 0
            || member.isMultibinding
        hasInputConfiguration = hasConstructionSource
            || member.withDependenciesParseState.hasArgument
        hasConstructionSourceConflict = member.scope != .input
            && constructionSourceCount > 1
    }
}
