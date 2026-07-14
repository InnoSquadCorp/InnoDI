import InnoDICore
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

struct DIContainerValidator {
    static func validate(
        model: DIContainerExpansionModel,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        let resolutionContext = DependencyResolutionContext(members: model.members)
        let memberByName = Dictionary(uniqueKeysWithValues: model.members.map { ($0.name, $0) })
        let locallyValidMemberNames = Set(
            model.members
                .filter(\.hasLocallyValidConstructionConfiguration)
                .map(\.name)
        )
        let dagValidationEnabled = model.options.validateDAG

        for (index, member) in model.members.enumerated() {
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
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.type),
                        message: SimpleDiagnostic.provideOpaqueTypeUnsupported(
                            memberName: member.name
                        )
                    )
                )
                hadErrors = true
            }

            if isImplicitlyUnwrappedOptionalType(member.type) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.type),
                        message: SimpleDiagnostic.provideIUOTypeUnsupported(
                            memberName: member.name
                        )
                    )
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
                context.diagnose(Diagnostic(node: Syntax(member.attribute), message: message))
                hadErrors = true
            } else if member.scope != .input,
                      member.withDependenciesParseState.hasArgument,
                      member.typeExpr == nil {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.attribute),
                        message: SimpleDiagnostic.provideWithRequiresTypeConstruction(
                            memberName: member.name
                        )
                    )
                )
                hadErrors = true
            }

            if member.closureHasWildcard {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.transientFactoryUnnamedParameters())
                )
                hadErrors = true
            }

            if member.scope == .shared && !hasFactory {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideSharedFactoryRequired())
                )
                hadErrors = true
            }

            if member.scope == .transient && !hasFactory {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideTransientFactoryRequired())
                )
                hadErrors = true
            }

            if member.scope == .input && hasInputConfiguration {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideInputInvalidConfiguration())
                )
                hadErrors = true
            }

            if member.scope != .input && member.escapingInput {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.attribute),
                        message: SimpleDiagnostic.provideEscapingInvalidScope(
                            memberName: member.name
                        )
                    )
                )
                hadErrors = true
            }

            if member.scope == .input,
               member.escapingInput,
               !supportsExplicitEscapingInput(member.type) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.type),
                        message: SimpleDiagnostic.provideEscapingNonFunctionType(
                            memberName: member.name
                        )
                    )
                )
                hadErrors = true
            }

            if member.scope == .input && member.asyncFactory != nil
                && member.factory == nil
                && member.typeExpr == nil
                && member.initializer == nil {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideAsyncFactoryInvalidScope())
                )
                hadErrors = true
            }

            if !hasConstructionSourceConflict,
               let asyncFactory = member.asyncFactory,
               !isAsyncClosureExpression(asyncFactory) {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideAsyncFactoryMustBeAsync())
                )
                hadErrors = true
            }

            if !hasConstructionSourceConflict, let factory = member.factory {
                if isAsyncClosureExpression(factory) || factoryExpressionContainsAwait(factory) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(factory),
                            message: SimpleDiagnostic.provideFactoryMustBeSync(memberName: member.name)
                        )
                    )
                    hadErrors = true
                }

                if isThrowingClosureExpression(factory) || factoryExpressionContainsPlainTry(factory) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(factory),
                            message: SimpleDiagnostic.provideFactoryMustNotThrow(memberName: member.name)
                        )
                    )
                    hadErrors = true
                }
            }

            if member.scope != .input && !member.concreteOptIn && requiresConcreteOptIn(type: member.type) {
                context.diagnose(
                    makeConcreteOptInDiagnostic(member: member)
                )
                hadErrors = true
            }

            // Configuration diagnostics own the declaration until its local
            // construction mode is coherent. Do not derive sibling lookup,
            // graph, or effect errors from a provider that code generation has
            // already excluded.
            guard member.hasLocallyValidConstructionConfiguration else {
                continue
            }

            let hardClosureNames = Set(member.hardClosureDependencies)
            let softClosureReferences = Dictionary(uniqueKeysWithValues: member.softClosureParameterReferences.map { ($0.name, $0) })
            let providerClosureReferences = Dictionary(uniqueKeysWithValues: member.providerClosureParameterReferences.map { ($0.name, $0) })
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
                            context.diagnose(
                                Diagnostic(
                                    node: callSite.node,
                                    message: SimpleDiagnostic.provideLazyEagerCall(
                                        memberName: member.name,
                                        dependencyName: callSite.dependencyName
                                    )
                                )
                            )
                            hadErrors = true
                        }
                    }
                }

                let providerNames = Set(providerClosureReferences.keys)
                if !providerNames.isEmpty {
                    for closure in sharedClosures {
                        for callSite in collectDirectDeferredEagerCalls(in: closure, dependencyNames: providerNames) {
                            context.diagnose(
                                Diagnostic(
                                    node: callSite.node,
                                    message: SimpleDiagnostic.provideProviderEagerCall(
                                        memberName: member.name,
                                        dependencyName: callSite.dependencyName
                                    )
                                )
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
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(softReference.token),
                            message: SimpleDiagnostic.provideLazyUnsupportedTarget(
                                memberName: member.name,
                                dependencyName: dependency
                            )
                        )
                    )
                    hadErrors = true
                    continue
                }

                if let providerReference = providerClosureReferences[dependency],
                   let referencedMember,
                   referencedMember.scope != .transient {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(providerReference.token),
                            message: SimpleDiagnostic.provideProviderNonTransientTarget(
                                memberName: member.name,
                                dependencyName: dependency,
                                targetScope: referencedMember.scope
                            )
                        )
                    )
                    hadErrors = true
                    continue
                }

                if let providerReference = providerClosureReferences[dependency],
                   let referencedMember,
                   referencedMember.scope == .transient,
                   referencedMember.isAsyncFactory {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(providerReference.token),
                            message: SimpleDiagnostic.provideProviderUnsupportedTarget(
                                memberName: member.name,
                                dependencyName: dependency
                            )
                        )
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

                    context.diagnose(
                        Diagnostic(
                            node: nodeSyntax,
                            message: SimpleDiagnostic.containerDependencyCycle(path: cycle.joined(separator: " -> "))
                        )
                    )
                    hadErrors = true
                }
            }
            if cycleResult.truncatedByDepthLimit, let firstMember = model.members.first {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(firstMember.attribute),
                        message: SimpleDiagnostic.containerDependencyCycle(
                            path: "cycle detection truncated at depth limit before validation completed"
                        )
                    )
                )
                hadErrors = true
            }
        }

        // Reserved-name collision check.
        //
        // The macro synthesizes private storage and helper bindings using a
        // fixed set of prefixes (see `DIContainerCodeGenerator` and
        // `SubContainerMacro`). A user-declared `@Provide` / `@SubContainer`
        // member that starts with one of these prefixes will collide with the
        // generated symbol and produce confusing Swift errors instead of an
        // InnoDI diagnostic. Reject up front so the user gets actionable
        // guidance.
        let reservedMemberPrefixes: [String] = [
            "_storage_",
            "_override_sub_",
            "_innoDISubBuild_",
            "_innoDIUnresolvedDependency",
            "_subBuildCell_",
            "_lazyCell_",
            "_lazySelfForSub"
        ]

        let allMembers: [(name: String, attribute: AttributeSyntax)] =
            model.members.map { (name: $0.name, attribute: $0.attribute) }
            + model.subContainerMembers.map { (name: $0.name, attribute: $0.attribute) }

        for entry in allMembers {
            for prefix in reservedMemberPrefixes where entry.name.hasPrefix(prefix) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(entry.attribute),
                        message: SimpleDiagnostic.containerReservedNamePrefix(
                            memberName: entry.name,
                            reservedPrefix: prefix
                        )
                    )
                )
                hadErrors = true
                break
            }
        }

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
        let memberScopeByName = Dictionary(
            uniqueKeysWithValues: model.members.map { ($0.name, $0.scope) }
        )
        let knownParentMemberNames = Set(memberScopeByName.keys)
        let reservedMemberNames = Set(model.members.map(\.name) + model.subContainerMembers.map(\.name))

        for sub in model.subContainerMembers {
            let generatedOverrideName = sub.overrideClosureName
            if reservedMemberNames.contains(generatedOverrideName) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(sub.bindingSyntax.pattern),
                        message: SimpleDiagnostic.subOverridesNameConflict(
                            memberName: sub.name,
                            generatedName: generatedOverrideName
                        )
                    )
                )
                hadErrors = true
            }

            let hasBindingWiringConflict = sub.hasWithDependencies && sub.hasBindingsArgument
            if hasBindingWiringConflict {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(sub.attribute),
                        message: SimpleDiagnostic.subBindingsConflictsWithWith(memberName: sub.name)
                    )
                )
                hadErrors = true
            }

            if !hasBindingWiringConflict, sub.hasInvalidBindings {
                context.diagnose(
                    Diagnostic(
                        node: sub.invalidBindingAnchorExpression.map(Syntax.init) ?? Syntax(sub.attribute),
                        message: SimpleDiagnostic.subInvalidBindings(memberName: sub.name)
                    )
                )
                hadErrors = true
                continue
            }

            var seenChildInputs: Set<String> = []
            for binding in sub.explicitBindings {
                if !seenChildInputs.insert(binding.childInputName).inserted {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(binding.childKeyPath),
                            message: SimpleDiagnostic.subDuplicateChildBinding(
                                memberName: sub.name,
                                childInputName: binding.childInputName
                            )
                        )
                    )
                    hadErrors = true
                }
            }

            // scope: is required and must parse as `.shared` / `.transient`.
            if sub.scope == nil {
                if let scopeExpression = sub.scopeExpressionSyntax {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(scopeExpression),
                            message: SimpleDiagnostic.subUnknownScope(
                                memberName: sub.name,
                                scopeName: sub.scopeName ?? scopeExpression.trimmedDescription
                            )
                        )
                    )
                } else {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(sub.attribute),
                            message: SimpleDiagnostic.subScopeRequired(memberName: sub.name)
                        )
                    )
                }
                hadErrors = true
                continue
            }

            if !hasBindingWiringConflict,
               let invalidLabel = sub.invalidSameNameWiringLabel {
                context.diagnose(
                    Diagnostic(
                        node: sub.sameNameWiringExpressionSyntax.map(Syntax.init) ?? Syntax(sub.attribute),
                        message: SimpleDiagnostic.subInvalidSameNameWiring(
                            memberName: sub.name,
                            label: invalidLabel
                        )
                    )
                )
                hadErrors = true
                continue
            }

            // Explicit same-name wiring must resolve to @Provide members on
            // the parent. `with:` diagnostics point at the keypath element.
            for parentName in sub.parentDependencies {
                if !knownParentMemberNames.contains(parentName) {
                    context.diagnose(
                        Diagnostic(
                            node: sub.parentReferenceSyntax(for: parentName).map(Syntax.init) ?? Syntax(sub.attribute),
                            message: SimpleDiagnostic.subUnknownParentMember(
                                memberName: sub.name,
                                parentMemberName: parentName
                            )
                        )
                    )
                    hadErrors = true
                }
            }

            for binding in sub.explicitBindings {
                let parentName = binding.parentMemberName
                if !knownParentMemberNames.contains(parentName) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(binding.parentKeyPath),
                            message: SimpleDiagnostic.subUnknownParentMember(
                                memberName: sub.name,
                                parentMemberName: parentName
                            )
                        )
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
                context.diagnose(
                    Diagnostic(
                        node: Syntax(sub.attribute),
                        message: SimpleDiagnostic.subAutoWiringAmbiguous(memberName: sub.name),
                        fixIts: makeSubAutoWiringAmbiguousFixIts(
                            attribute: sub.attribute,
                            parentMemberNames: parentCandidates
                        )
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
                    context.diagnose(
                        Diagnostic(
                            node: diagnosticNode,
                            message: SimpleDiagnostic.subSharedParentMustNotBeTransient(
                                memberName: sub.name,
                                parentMemberName: parentName
                            )
                        )
                    )
                    hadErrors = true
                }
            }
        }

        // Warn when a closure parameter uses a typealias that
        // aliases `Lazy<T>` or `Provider<T>`. The macro resolves deferred
        // wrapper kinds from written syntax, so typealiased spellings fall
        // through to `.hard` silently. This check collects same-file
        // typealiases and flags any closure parameter whose bare identifier
        // matches one of them. Cross-file aliases stay invisible.
        //
        // Anchor selection: we need any member's attribute syntax to walk up
        // to `SourceFileSyntax`. An empty container returns early in
        // `DIContainerMacro.expansion` before reaching the validator, so
        // reaching this point with both collections empty is impossible.
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
                            context.diagnose(
                                Diagnostic(
                                    node: Syntax(reference.token),
                                    message: SimpleDiagnostic.provideLazyAliased(
                                        parameterName: reference.name,
                                        aliasName: aliasName
                                    )
                                )
                            )
                        case .provider:
                            context.diagnose(
                                Diagnostic(
                                    node: Syntax(reference.token),
                                    message: SimpleDiagnostic.provideProviderAliased(
                                        parameterName: reference.name,
                                        aliasName: aliasName
                                    )
                                )
                            )
                        }
                    }
                }
            }
        }

        return !hadErrors
    }
}
