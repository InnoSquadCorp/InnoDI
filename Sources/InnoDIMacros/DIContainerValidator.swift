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
