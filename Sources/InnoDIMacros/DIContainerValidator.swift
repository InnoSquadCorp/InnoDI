import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct DIContainerValidator {
    static func validate(
        model: DIContainerExpansionModel,
        declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        let resolutionContext = DependencyResolutionContext(members: model.members)
        let memberByName = Dictionary(
            model.members.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let locallyValidMemberNames = Set(
            model.members
                .filter(\.hasLocallyValidConstructionConfiguration)
                .map(\.name)
        )
        let dagValidationEnabled = model.options.validateDAG

        var hadErrors = false
        hadErrors = validateGeneratedSymbolCollisions(
            model: model,
            context: context
        ) || hadErrors
        hadErrors = validateManagedMembers(
            model: model,
            resolutionContext: resolutionContext,
            memberByName: memberByName,
            dagValidationEnabled: dagValidationEnabled,
            context: context
        ) || hadErrors
        hadErrors = validateDependencyCycles(
            model: model,
            resolutionContext: resolutionContext,
            memberByName: memberByName,
            locallyValidMemberNames: locallyValidMemberNames,
            dagValidationEnabled: dagValidationEnabled,
            context: context
        ) || hadErrors
        hadErrors = validateReservedDeclarationNames(
            declaration: declaration,
            context: context
        ) || hadErrors
        hadErrors = validateReservedQualifierScopes(
            declaration: declaration,
            context: context
        ) || hadErrors
        hadErrors = validateSubContainerMembers(
            model: model,
            memberByName: memberByName,
            context: context
        ) || hadErrors
        validateDeferredWrapperAliases(
            model: model,
            context: context
        )
        return !hadErrors
    }

    /// Rejects managed members whose generated support symbols collide.
    private static func validateGeneratedSymbolCollisions(
        model: DIContainerExpansionModel,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for collision in generatedPeerSymbolCollisions(in: model) {
            context.emit(
                SimpleDiagnostic.containerGeneratedSymbolCollision(
                    conflictingMemberName: collision.conflictingMemberName,
                    generatedName: collision.generatedName,
                    firstMemberName: collision.firstMemberName
                ),
                at: collision.conflictingAnchor,
                notes: [
                    Note(
                        node: collision.firstAnchor,
                        message: SimpleNote(
                            "The first claim for generated support symbol '\(collision.generatedName)' comes from managed member '\(collision.firstMemberName)' here.",
                            code: .containerGeneratedSymbolCollision,
                            suffix: "first-claim"
                        )
                    )
                ]
            )
            hadErrors = true
        }
        return hadErrors
    }

    /// Per-member declaration checks: factory parameter spelling, property
    /// type shape, construction-source configuration, scope and effect
    /// compatibility, deferred-wrapper usage, and declaration-order
    /// dependency availability.
    private static func validateManagedMembers(
        model: DIContainerExpansionModel,
        resolutionContext: DependencyResolutionContext,
        memberByName: [String: ProvideMemberModel],
        dagValidationEnabled: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for (index, member) in model.members.enumerated() {
            let escapedFactoryParameters = member.closureParameterReferences.filter {
                isEscapedInnoDIIdentifier($0.token)
            }
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

            if escapedFactoryParameters.isEmpty {
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
            }

            let constructionSourceCount = [
                member.factory != nil,
                member.asyncFactory != nil,
                member.typeExpr != nil,
                member.initializer != nil,
            ].filter { $0 }.count
            let hasFactory = constructionSourceCount > 0
            let hasInputConfiguration = hasFactory
                || member.withDependenciesParseState.hasArgument
            let hasConstructionSourceConflict = member.scope != .input
                && constructionSourceCount > 1

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

            if hasConstructionSourceConflict {
                let message: SimpleDiagnostic
                if constructionSourceCount == 2,
                   member.factory != nil,
                   member.asyncFactory != nil {
                    message = .provideFactoryConflict()
                } else {
                    message = .provideConstructionSourceConflict(
                        memberName: member.name
                    )
                }
                context.emit(
                    message,
                    at: Syntax(member.attribute)
                )
                hadErrors = true
            } else if member.scope != .input,
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

            if member.scope == .shared && !hasFactory {
                context.emit(
                    SimpleDiagnostic.provideSharedFactoryRequired(),
                    at: Syntax(member.attribute)
                )
                hadErrors = true
            }

            if member.scope == .transient && !hasFactory {
                context.emit(
                    SimpleDiagnostic.provideTransientFactoryRequired(),
                    at: Syntax(member.attribute)
                )
                hadErrors = true
            }

            if member.scope == .input && hasInputConfiguration {
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

            if member.scope == .input && member.asyncFactory != nil
                && member.factory == nil
                && member.typeExpr == nil
                && member.initializer == nil {
                context.emit(
                    SimpleDiagnostic.provideAsyncFactoryInvalidScope(),
                    at: Syntax(member.attribute)
                )
                hadErrors = true
            }

            if !hasConstructionSourceConflict,
               let asyncFactory = member.asyncFactory,
               !isAsyncClosureExpression(asyncFactory) {
                context.emit(
                    SimpleDiagnostic.provideAsyncFactoryMustBeAsync(),
                    at: Syntax(member.attribute)
                )
                hadErrors = true
            }

            if !hasConstructionSourceConflict, let factory = member.factory {
                if isAsyncClosureExpression(factory) || factoryExpressionContainsAwait(factory) {
                    context.emit(
                        SimpleDiagnostic.provideFactoryMustBeSync(memberName: member.name),
                        at: Syntax(factory)
                    )
                    hadErrors = true
                }

                if isThrowingClosureExpression(factory) || factoryExpressionContainsPlainTry(factory) {
                    context.emit(
                        SimpleDiagnostic.provideFactoryMustNotThrow(memberName: member.name),
                        at: Syntax(factory)
                    )
                    hadErrors = true
                }
            }

            // Configuration diagnostics own the declaration until its local
            // construction mode is coherent. Do not derive sibling lookup,
            // graph, or effect errors from a provider that code generation has
            // already excluded.
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
            if !effectMismatchNames.isEmpty {
                hadErrors = true
            }

            if member.scope == .shared {
                let sharedClosures = [member.factory, member.asyncFactory].compactMap { $0?.as(ClosureExprSyntax.self) }
                let lazyNames = Set(softClosureReferences.keys)
                if !lazyNames.isEmpty {
                    for closure in sharedClosures {
                        for callSite in collectDirectDeferredEagerCalls(in: closure, dependencyNames: lazyNames) {
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
                }

                let providerNames = Set(providerClosureReferences.keys)
                if !providerNames.isEmpty {
                    for closure in sharedClosures {
                        for callSite in collectDirectDeferredEagerCalls(in: closure, dependencyNames: providerNames) {
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
                }
            }

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

                let status = resolutionContext.status(of: dependency, forMemberAt: index)
                switch status {
                case .available:
                    break
                case .unknown:
                    if dagValidationEnabled || member.scope == .transient {
                        context.diagnose(
                            makeUnresolvedFactoryParameterDiagnostic(
                                member: member,
                                dependencyName: dependency,
                                resolutionContext: resolutionContext,
                                memberIndex: index
                            )
                        )
                        hadErrors = true
                    }
                case .unavailable:
                    guard dagValidationEnabled else { continue }
                    // Soft (Lazy<T>) and provider (Provider<T>) edges
                    // intentionally escape declaration-order availability:
                    // a generated local deferred cell lets a forward
                    // reference resolve safely once init completes, and
                    // `Provider<T>` reaches its transient target through
                    // the same late-binding resolver. Only hard edges
                    // still need to be reachable in declaration order.
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

            for dependency in deduplicateStrings(member.withDependencies) {
                if effectMismatchNames.contains(dependency) {
                    continue
                }
                let referencedMember = memberByName[dependency]
                if let referencedMember,
                   !referencedMember.hasLocallyValidConstructionConfiguration {
                    continue
                }
                guard dagValidationEnabled || member.scope == .transient else { continue }
                switch resolutionContext.status(of: dependency, forMemberAt: index) {
                case .available:
                    break
                case .unknown:
                    context.diagnose(
                        makeUnresolvedWithDependencyDiagnostic(
                            member: member,
                            dependencyName: dependency,
                            resolutionContext: resolutionContext,
                            memberIndex: index
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

        }
        return hadErrors
    }

    /// Local hard-edge cycle detection over locally valid members.
    private static func validateDependencyCycles(
        model: DIContainerExpansionModel,
        resolutionContext: DependencyResolutionContext,
        memberByName: [String: ProvideMemberModel],
        locallyValidMemberNames: Set<String>,
        dagValidationEnabled: Bool,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        if dagValidationEnabled {
            var adjacency: [String: [String]] = [:]
            for index in model.members.indices {
                let member = model.members[index]
                guard member.hasLocallyValidConstructionConfiguration else {
                    continue
                }
                // Exclude deferred edges (`Lazy<T>` / `Provider<T>`) from
                // cycle detection so intentionally-broken graphs compile
                // cleanly. The corresponding hard-only graph still
                // participates in declaration-order availability checks via
                // status(…).
                let dependencies = resolutionContext
                    .hardGraphDependencies(forMemberAt: index)
                    .filter { locallyValidMemberNames.contains($0) }
                adjacency[member.name] = deduplicateStrings(dependencies)
            }

            let cycleResult = InnoDICore.analyzeDependencyCycles(adjacency: adjacency)
            let cycles = cycleResult.cycles
            if !cycles.isEmpty {
                for cycle in cycles {
                    guard let start = cycle.first else { continue }
                    let nodeSyntax: Syntax
                    if let member = memberByName[start] {
                        nodeSyntax = Syntax(member.attribute)
                    } else if let firstMember = model.members.first {
                        nodeSyntax = Syntax(firstMember.attribute)
                    } else {
                        continue
                    }

                    context.emit(
                        SimpleDiagnostic.containerDependencyCycle(path: cycle.joined(separator: " -> ")),
                        at: nodeSyntax
                    )
                    hadErrors = true
                }
            }
            if cycleResult.truncatedByDepthLimit, let firstMember = model.members.first {
                context.emit(
                    SimpleDiagnostic.containerDependencyCycle(
                        path: "cycle detection truncated at depth limit before validation completed"
                    ),
                    at: Syntax(firstMember.attribute)
                )
                hadErrors = true
            }
        }
        return hadErrors
    }

    /// Rejects direct declarations that shadow generated module qualifiers
    /// or reserved generated-member prefixes.
    private static func validateReservedDeclarationNames(
        declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        // Reserved-name collision check.
        //
        // The macro synthesizes private storage and helper bindings using a
        // fixed set of prefixes (see `DIContainerCodeGenerator` and
        // `SubContainerMacro`). A user-declared `@Provide` / `@SubContainer`
        // member that starts with one of these prefixes will collide with the
        // generated symbol and produce confusing Swift errors instead of an
        // InnoDI diagnostic. Reject up front so the user gets actionable
        // guidance.
        for entry in directContainerDeclarationNames(in: declaration) {
            let shadowsGeneratedModuleQualifier = entry.name == "InnoDI"
                || (entry.namespace == .type
                    && ["Swift", "_Concurrency"].contains(entry.name))
            if shadowsGeneratedModuleQualifier {
                context.emit(
                    SimpleDiagnostic.containerReservedModuleName(
                        memberName: entry.name
                    ),
                    at: entry.anchor
                )
                hadErrors = true
                continue
            }
            for prefix in reservedGeneratedMemberPrefixes where entry.name.hasPrefix(prefix) {
                context.emit(
                    SimpleDiagnostic.containerReservedNamePrefix(
                        memberName: entry.name,
                        reservedPrefix: prefix
                    ),
                    at: entry.anchor
                )
                hadErrors = true
                break
            }
        }
        return hadErrors
    }

    /// Rejects enclosing-scope declarations that shadow generated
    /// module-qualifier lookups.
    private static func validateReservedQualifierScopes(
        declaration: some DeclGroupSyntax,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for entry in reservedGeneratedQualifierScopeDeclarations(
            for: declaration,
            lexicalContext: context.lexicalContext
        ) {
            context.emit(
                SimpleDiagnostic.containerReservedModuleName(
                    memberName: entry.name
                ),
                at: generatedNameDiagnosticAnchor(
                    for: entry,
                    attachedTo: declaration
                )
            )
            hadErrors = true
        }
        return hadErrors
    }

    /// `@SubContainer` member checks: scope spelling, wiring-form conflicts,
    /// parent-member references, and auto-wiring ambiguity.
    private static func validateSubContainerMembers(
        model: DIContainerExpansionModel,
        memberByName: [String: ProvideMemberModel],
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        // Sub-container validation.
        //
        // The parser has already rejected properties carrying both
        // `@Provide` and `@SubContainer` (see `sub.conflicts-with-provide`
        // in `DIContainerParser`). We still need to check:
        //   - scope argument presence and spelling
        //   - `with:` keypaths reference real parent members
        //   - implicit auto-wiring is only allowed when there is at most one
        //     parent @Provide candidate; larger parents must opt into
        //     `with:` / `bindings:` so child inputs are unambiguous
        //   - `.shared` sub-containers do not auto-wire through a
        //     `.transient` parent member (would try to read a missing
        //     `_storage_<name>` inside init)
        let memberScopeByName = memberByName.mapValues(\.scope)
        let knownParentMemberNames = Set(memberScopeByName.keys)
        let reservedMemberNames = Set(model.members.map(\.name) + model.subContainerMembers.map(\.name))

        for sub in model.subContainerMembers {
            let generatedOverrideName = sub.overrideClosureName
            if reservedMemberNames.contains(generatedOverrideName) {
                context.emit(
                    SimpleDiagnostic.subOverridesNameConflict(
                        memberName: sub.name,
                        generatedName: generatedOverrideName
                    ),
                    at: Syntax(sub.bindingSyntax.pattern)
                )
                hadErrors = true
            }

            let hasBindingWiringConflict = sub.hasWithDependencies && sub.hasBindingsArgument
            if hasBindingWiringConflict {
                context.emit(
                    SimpleDiagnostic.subBindingsConflictsWithWith(memberName: sub.name),
                    at: Syntax(sub.attribute)
                )
                hadErrors = true
            }

            if !hasBindingWiringConflict, sub.hasInvalidBindings {
                context.emit(
                    SimpleDiagnostic.subInvalidBindings(memberName: sub.name),
                    at: sub.invalidBindingAnchorExpression.map(Syntax.init) ?? Syntax(sub.attribute)
                )
                hadErrors = true
                continue
            }

            var seenChildInputs: Set<String> = []
            for binding in sub.explicitBindings {
                if !seenChildInputs.insert(binding.childInputName).inserted {
                    context.emit(
                        SimpleDiagnostic.subDuplicateChildBinding(
                            memberName: sub.name,
                            childInputName: binding.childInputName
                        ),
                        at: Syntax(binding.childKeyPath)
                    )
                    hadErrors = true
                }
            }

            // scope: is required and must parse as `.shared` / `.transient`.
            if sub.scope == nil {
                if let scopeExpression = sub.scopeExpressionSyntax {
                    context.emit(
                        SimpleDiagnostic.subUnknownScope(
                            memberName: sub.name,
                            scopeName: sub.scopeName ?? scopeExpression.trimmedDescription
                        ),
                        at: Syntax(scopeExpression)
                    )
                } else {
                    context.emit(
                        SimpleDiagnostic.subScopeRequired(memberName: sub.name),
                        at: Syntax(sub.attribute)
                    )
                }
                hadErrors = true
                continue
            }

            if !hasBindingWiringConflict,
               let invalidLabel = sub.invalidSameNameWiringLabel {
                context.emit(
                    SimpleDiagnostic.subInvalidSameNameWiring(
                        memberName: sub.name,
                        label: invalidLabel
                    ),
                    at: sub.sameNameWiringExpressionSyntax.map(Syntax.init) ?? Syntax(sub.attribute)
                )
                hadErrors = true
                continue
            }

            // Explicit same-name wiring must resolve to @Provide members on
            // the parent. `with:` diagnostics point at the keypath element.
            for parentName in sub.parentDependencies {
                if !knownParentMemberNames.contains(parentName) {
                    context.emit(
                        SimpleDiagnostic.subUnknownParentMember(
                            memberName: sub.name,
                            parentMemberName: parentName
                        ),
                        at: sub.parentReferenceSyntax(for: parentName).map(Syntax.init) ?? Syntax(sub.attribute)
                    )
                    hadErrors = true
                }
            }

            for binding in sub.explicitBindings {
                let parentName = binding.parentMemberName
                if !knownParentMemberNames.contains(parentName) {
                    context.emit(
                        SimpleDiagnostic.subUnknownParentMember(
                            memberName: sub.name,
                            parentMemberName: parentName
                        ),
                        at: Syntax(binding.parentKeyPath)
                    )
                    hadErrors = true
                }
            }

            let usesImplicitSubContainerParentNames = sub.sameNameWiring == .omitted
                && !sub.hasBindingsArgument

            if usesImplicitSubContainerParentNames,
               !canResolveImplicitSubContainerParentNames(
                    member: sub,
                    autoWireParentMemberNames: model.members.map(\.name)
               ) {
                let parentCandidates = model.members.map(\.name)
                context.emit(
                    SimpleDiagnostic.subAutoWiringAmbiguous(memberName: sub.name),
                    at: Syntax(sub.attribute),
                    fixIts: makeSubAutoWiringAmbiguousFixIts(
                        attribute: sub.attribute,
                        parentMemberNames: parentCandidates
                    )
                )
                hadErrors = true
            }

            // `.shared` sub-containers read parent members through private
            // `_storage_<name>` at init time, so `.transient` parents are
            // off-limits (no storage slot exists for them). Implicit
            // auto-wiring can only select a single parent member; otherwise
            // the ambiguity diagnostic above requires explicit wiring.
            guard sub.scope == .shared else { continue }
            let wiredParents: [String]
            if sub.hasBindingsArgument {
                wiredParents = sub.explicitBindings.map(\.parentMemberName)
            } else if sub.hasExplicitSameNameWiring {
                wiredParents = sub.parentDependencies
            } else if sub.sameNameWiring == .omitted {
                wiredParents = canResolveImplicitSubContainerParentNames(
                    member: sub,
                    autoWireParentMemberNames: model.members.map(\.name)
                )
                    ? resolvedSubContainerParentNames(
                        member: sub,
                        autoWireParentMemberNames: model.members.map(\.name)
                    )
                    : []
            } else {
                wiredParents = []
            }
            for parentName in wiredParents where knownParentMemberNames.contains(parentName) {
                if memberScopeByName[parentName] == .transient {
                    let diagnosticNode = sub.parentBindingKeyPathSyntax(for: parentName).map(Syntax.init)
                        ?? sub.parentReferenceSyntax(for: parentName).map(Syntax.init)
                        ?? Syntax(sub.attribute)
                    context.emit(
                        SimpleDiagnostic.subSharedParentMustNotBeTransient(
                            memberName: sub.name,
                            parentMemberName: parentName
                        ),
                        at: diagnosticNode
                    )
                    hadErrors = true
                }
            }
        }
        return hadErrors
    }

    /// Warns when factory closure parameters spell `Lazy`/`Provider`
    /// through a same-file typealias. Warning-only: this check never fails
    /// validation, so it does not participate in error accumulation.
    private static func validateDeferredWrapperAliases(
        model: DIContainerExpansionModel,
        context: some MacroExpansionContext
    ) {
        // Warn when a closure parameter uses a typealias that
        // aliases `Lazy<T>` or `Provider<T>`. The macro resolves deferred
        // wrapper kinds from written syntax, so typealiased spellings fall
        // through to `.hard` silently. This check collects same-file
        // typealiases and flags any closure parameter whose bare identifier
        // matches one of them. Cross-file aliases stay invisible.
        //
        // Anchor selection: we need any managed member's attribute syntax to
        // walk up to `SourceFileSyntax`. A container with no managed members
        // still reaches this validator for direct-name checks and simply has
        // no deferred-wrapper aliases to inspect.
        let aliasAnchor: Syntax? = model.members.first.map { Syntax($0.attribute) }
            ?? model.subContainerMembers.first.map { Syntax($0.attribute) }
        if let anchor = aliasAnchor {
            let aliases = collectLazyProviderAliases(anchoredBy: anchor)
            if !aliases.isEmpty {
                for member in model.members {
                    for reference in member.closureParameterReferences {
                        guard reference.kind == .hard else { continue }
                        guard let aliasedKind = aliasedDeferredWrapperKind(
                            for: reference.type,
                            aliases: aliases
                        ) else { continue }
                        let aliasName = reference.type?
                            .trimmedDescription ?? reference.name
                        switch aliasedKind {
                        case .lazy:
                            context.emit(
                                SimpleDiagnostic.provideLazyAliased(
                                    parameterName: reference.name,
                                    aliasName: aliasName
                                ),
                                at: Syntax(reference.token)
                            )
                        case .provider:
                            context.emit(
                                SimpleDiagnostic.provideProviderAliased(
                                    parameterName: reference.name,
                                    aliasName: aliasName
                                ),
                                at: Syntax(reference.token)
                            )
                        }
                    }
                }
            }
        }
    }
}
