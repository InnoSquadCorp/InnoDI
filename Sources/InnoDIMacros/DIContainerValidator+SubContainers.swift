import InnoDICore
import SwiftSyntax
import SwiftSyntaxMacros

// MARK: - Managed @SubContainer members

extension DIContainerValidator {
    /// Validates child wiring in phases so malformed argument shapes cannot
    /// leak into parent lookup or scope-derived diagnostics.
    static func validateSubContainerMembers(
        model: DIContainerExpansionModel,
        memberByName: [String: ProvideMemberModel],
        context: some MacroExpansionContext
    ) -> Bool {
        let state = SubContainerValidationState(
            model: model,
            memberByName: memberByName
        )
        var hadErrors = false
        for subContainer in model.subContainerMembers {
            let preflight = validateSubContainerPreflight(
                member: subContainer,
                state: state,
                context: context
            )
            hadErrors = preflight.hadErrors || hadErrors
            guard preflight.canValidateReferences else { continue }

            hadErrors = validateSubContainerParentReferences(
                member: subContainer,
                knownParentMemberNames: state.knownParentMemberNames,
                context: context
            ) || hadErrors
            hadErrors = validateSubContainerAutoWiring(
                member: subContainer,
                parentMemberNames: state.parentMemberNames,
                context: context
            ) || hadErrors
            hadErrors = validateSharedSubContainerParentScopes(
                member: subContainer,
                state: state,
                context: context
            ) || hadErrors
        }
        return hadErrors
    }

    /// Checks argument shape and scope before any parent-name resolution.
    private static func validateSubContainerPreflight(
        member: SubContainerMemberModel,
        state: SubContainerValidationState,
        context: some MacroExpansionContext
    ) -> SubContainerPreflightResult {
        var hadErrors = false
        let generatedOverrideName = member.overrideClosureName
        if state.reservedMemberNames.contains(generatedOverrideName) {
            context.emit(
                SimpleDiagnostic.subOverridesNameConflict(
                    memberName: member.name,
                    generatedName: generatedOverrideName
                ),
                at: Syntax(member.bindingSyntax.pattern)
            )
            hadErrors = true
        }

        let hasBindingWiringConflict = member.hasWithDependencies
            && member.hasBindingsArgument
        if hasBindingWiringConflict {
            context.emit(
                SimpleDiagnostic.subBindingsConflictsWithWith(
                    memberName: member.name
                ),
                at: Syntax(member.attribute)
            )
            hadErrors = true
        }
        if !hasBindingWiringConflict, member.hasInvalidBindings {
            context.emit(
                SimpleDiagnostic.subInvalidBindings(memberName: member.name),
                at: member.invalidBindingAnchorExpression.map(Syntax.init)
                    ?? Syntax(member.attribute)
            )
            return SubContainerPreflightResult(
                hadErrors: true,
                canValidateReferences: false
            )
        }

        var seenChildInputs: Set<String> = []
        for binding in member.explicitBindings {
            if !seenChildInputs.insert(binding.childInputName).inserted {
                context.emit(
                    SimpleDiagnostic.subDuplicateChildBinding(
                        memberName: member.name,
                        childInputName: binding.childInputName
                    ),
                    at: Syntax(binding.childKeyPath)
                )
                hadErrors = true
            }
        }

        guard member.scope != nil else {
            if let scopeExpression = member.scopeExpressionSyntax {
                context.emit(
                    SimpleDiagnostic.subUnknownScope(
                        memberName: member.name,
                        scopeName: member.scopeName
                            ?? scopeExpression.trimmedDescription
                    ),
                    at: Syntax(scopeExpression)
                )
            } else {
                context.emit(
                    SimpleDiagnostic.subScopeRequired(memberName: member.name),
                    at: Syntax(member.attribute)
                )
            }
            return SubContainerPreflightResult(
                hadErrors: true,
                canValidateReferences: false
            )
        }

        if !hasBindingWiringConflict,
           let invalidLabel = member.invalidSameNameWiringLabel {
            context.emit(
                SimpleDiagnostic.subInvalidSameNameWiring(
                    memberName: member.name,
                    label: invalidLabel
                ),
                at: member.sameNameWiringExpressionSyntax.map(Syntax.init)
                    ?? Syntax(member.attribute)
            )
            return SubContainerPreflightResult(
                hadErrors: true,
                canValidateReferences: false
            )
        }

        return SubContainerPreflightResult(
            hadErrors: hadErrors,
            canValidateReferences: true
        )
    }

    /// Resolves explicit `with:` and `bindings:` parent references.
    private static func validateSubContainerParentReferences(
        member: SubContainerMemberModel,
        knownParentMemberNames: Set<String>,
        context: some MacroExpansionContext
    ) -> Bool {
        var hadErrors = false
        for parentName in member.parentDependencies {
            guard !knownParentMemberNames.contains(parentName) else { continue }
            context.emit(
                SimpleDiagnostic.subUnknownParentMember(
                    memberName: member.name,
                    parentMemberName: parentName
                ),
                at: member.parentReferenceSyntax(for: parentName)
                    .map(Syntax.init) ?? Syntax(member.attribute)
            )
            hadErrors = true
        }
        for binding in member.explicitBindings {
            let parentName = binding.parentMemberName
            guard !knownParentMemberNames.contains(parentName) else { continue }
            context.emit(
                SimpleDiagnostic.subUnknownParentMember(
                    memberName: member.name,
                    parentMemberName: parentName
                ),
                at: Syntax(binding.parentKeyPath)
            )
            hadErrors = true
        }
        return hadErrors
    }

    /// Requires an explicit mapping when implicit same-name wiring is
    /// ambiguous, and offers the complete parent candidate list as a fix-it.
    private static func validateSubContainerAutoWiring(
        member: SubContainerMemberModel,
        parentMemberNames: [String],
        context: some MacroExpansionContext
    ) -> Bool {
        let usesImplicitParentNames = member.sameNameWiring == .omitted
            && !member.hasBindingsArgument
        guard usesImplicitParentNames,
              !canResolveImplicitSubContainerParentNames(
                member: member,
                autoWireParentMemberNames: parentMemberNames
              ) else {
            return false
        }
        context.emit(
            SimpleDiagnostic.subAutoWiringAmbiguous(memberName: member.name),
            at: Syntax(member.attribute),
            fixIts: makeSubAutoWiringAmbiguousFixIts(
                attribute: member.attribute,
                parentMemberNames: parentMemberNames
            )
        )
        return true
    }

    /// A shared child reads parent storage during initialization, so every
    /// resolved parent must itself own stable storage.
    private static func validateSharedSubContainerParentScopes(
        member: SubContainerMemberModel,
        state: SubContainerValidationState,
        context: some MacroExpansionContext
    ) -> Bool {
        guard member.scope == .shared else { return false }
        let wiredParents = resolvedParentNames(
            for: member,
            autoWireParentMemberNames: state.parentMemberNames
        )
        var hadErrors = false
        for parentName in wiredParents
        where state.knownParentMemberNames.contains(parentName) {
            guard state.memberScopeByName[parentName] == .transient else {
                continue
            }
            let diagnosticNode = member.parentBindingKeyPathSyntax(
                for: parentName
            ).map(Syntax.init)
                ?? member.parentReferenceSyntax(for: parentName)
                    .map(Syntax.init)
                ?? Syntax(member.attribute)
            context.emit(
                SimpleDiagnostic.subSharedParentMustNotBeTransient(
                    memberName: member.name,
                    parentMemberName: parentName
                ),
                at: diagnosticNode
            )
            hadErrors = true
        }
        return hadErrors
    }

    private static func resolvedParentNames(
        for member: SubContainerMemberModel,
        autoWireParentMemberNames: [String]
    ) -> [String] {
        if member.hasBindingsArgument {
            return member.explicitBindings.map(\.parentMemberName)
        }
        if member.hasExplicitSameNameWiring {
            return member.parentDependencies
        }
        if member.sameNameWiring == .omitted,
           canResolveImplicitSubContainerParentNames(
            member: member,
            autoWireParentMemberNames: autoWireParentMemberNames
           ) {
            return resolvedSubContainerParentNames(
                member: member,
                autoWireParentMemberNames: autoWireParentMemberNames
            )
        }
        return []
    }
}

private struct SubContainerValidationState {
    let memberScopeByName: [String: ProvideScope]
    let knownParentMemberNames: Set<String>
    let reservedMemberNames: Set<String>
    let parentMemberNames: [String]

    init(
        model: DIContainerExpansionModel,
        memberByName: [String: ProvideMemberModel]
    ) {
        memberScopeByName = memberByName.mapValues(\.scope)
        knownParentMemberNames = Set(memberScopeByName.keys)
        reservedMemberNames = Set(
            model.members.map(\.name) + model.subContainerMembers.map(\.name)
        )
        parentMemberNames = model.members.map(\.name)
    }
}

private struct SubContainerPreflightResult {
    let hadErrors: Bool
    let canValidateReferences: Bool
}
