import InnoDICore
import SwiftSyntax
import SwiftSyntaxMacros

/// Keep the opt-in prototype closed over the forms whose ownership and
/// lexical construction can be faithfully reproduced. Legacy models never
/// enter this validation, including literal generateOwned: false.
func validateOwnedContainer(
    model: DIContainerExpansionModel,
    declaration: some DeclGroupSyntax,
    context: some MacroExpansionContext
) -> Bool {
    guard model.options.generateOwned else { return false }
    var hadErrors = false
    if !model.ownedMainActor,
       let actor = detectConflictingGlobalActor(in: declaration.attributes) {
        context.emit(
            SimpleDiagnostic.containerOwnedUnsupported("custom global actor '@\(actor)'"),
            at: declaration
        )
        hadErrors = true
    }
    if !model.options.validateDAG {
        let attribute = InnoDICore.findDIContainerAttribute(in: declaration.attributes)
        context.emit(
            SimpleDiagnostic.containerOwnedRequiresDAG(),
            at: attribute.flatMap { extractArgumentExpression(label: "validateDAG", from: $0) }
                .map(Syntax.init) ?? Syntax(declaration)
        )
        hadErrors = true
    }
    // The legacy direct-name validator reserves _Concurrency only in type
    // position. Owned construction additionally emits _Concurrency.Task calls.
    for entry in directContainerDeclarationNames(in: declaration)
        where entry.namespace == .value && entry.name == "_Concurrency" {
        context.emit(SimpleDiagnostic.containerReservedModuleName(memberName: entry.name), at: entry.anchor)
        hadErrors = true
    }
    if let conflict = directContainerDeclarationNames(in: declaration)
        .first(where: { $0.name == "makeOwned" || $0.name == "makeOwnedWithOverrides"
            || (!model.asyncSharedMembers.isEmpty && $0.name == "withPrepared") }) {
        context.emit(SimpleDiagnostic.containerOwnedNameConflict(name: conflict.name), at: conflict.anchor)
        hadErrors = true
    }
    for member in model.members {
        if !model.ownedMainActor,
           let attribute = ownedMemberActorAttribute(member.bindingSyntax) {
            context.emit(
                SimpleDiagnostic.containerOwnedUnsupported("per-member global-actor isolation on '\(member.name)'"),
                at: attribute
            )
            hadErrors = true
        }
        let unsupported: String?
        if member.isAssistedInput || member.assistedFactoryChildType != nil {
            unsupported = "assisted input/factory member '\(member.name)'"
        } else if member.scope == .transient, member.isAsyncFactory {
            unsupported = "async transient provider '\(member.name)'"
        } else if member.isMultibinding || !member.collectionMetadataEntries.isEmpty {
            unsupported = "collection provider '\(member.name)'"
        } else {
            unsupported = nil
        }
        if let unsupported {
            context.emit(SimpleDiagnostic.containerOwnedUnsupported(unsupported), at: member.attribute)
            hadErrors = true
        }
    }
    for child in model.subContainerMembers {
        if !model.ownedMainActor,
           let attribute = ownedMemberActorAttribute(child.bindingSyntax) {
            context.emit(
                SimpleDiagnostic.containerOwnedUnsupported("per-member global-actor isolation on '\(child.name)'"),
                at: attribute
            )
            hadErrors = true
        }
        if child.scope != .shared || !child.featureRoots.isEmpty {
            context.emit(
                SimpleDiagnostic.containerOwnedUnsupported("transient or feature-root child '\(child.name)'"),
                at: child.attribute
            )
            hadErrors = true
        }
    }
    return hadErrors
}

/// A member-isolated accessor must not silently become unisolated in the view.
/// Container-wide MainActor generation is the supported isolation boundary.
private func ownedMemberActorAttribute(_ binding: PatternBindingSyntax) -> AttributeSyntax? {
    guard let declaration = binding.parent?.parent?.as(VariableDeclSyntax.self) else { return nil }
    return declaration.attributes.compactMap { $0.as(AttributeSyntax.self) }.first { attribute in
        let name = attribute.attributeName.trimmedDescription.split(separator: ".").last ?? ""
        return name.hasSuffix("Actor")
    }
}
