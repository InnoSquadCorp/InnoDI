//
//  DISubContainerChildOverridesCheck.swift
//  InnoDIMacros
//
//  Phase N-3 — best-effort, same-file detection for child containers that
//  do not declare any override-generating members.
//
//  `@SubContainer` always adds a `<name>Overrides: ((inout <Child>.Overrides)
//  -> Void)?` slot to the parent's nested `Overrides` struct. When the child
//  has no `.shared`, `.transient`, or `@SubContainer` members, the child's
//  own macro expansion skips emitting `struct Overrides`, and the parent's
//  slot dangles — it references a type that will never exist. This module
//  walks the parent container's source file to spot that case and emit
//  `sub.child-overrides-missing`.
//
//  Cross-file / cross-module children cannot be seen from here and are
//  handled conservatively: if the child decl is not found in the same
//  file, the check returns `.unknown` and the caller stays silent. The
//  build-support validator fills in the cross-module gap.
//
//  Known limitations (all `.unknown` at detection time):
//    - typealiases that rename the child type (`typealias Feat =
//      FeatureContainer` + `@SubContainer … var x: Feat`) — the walk
//      matches on bare name, not aliased.
//    - child containers defined inside another type body (the walk only
//      iterates top-level source-file statements).
//    - child containers in a different source file of the same module
//      (build-support validator handles this).
//

import SwiftSyntax

internal enum SubContainerChildMembership {
    case hasOverrideableMember
    case inputOnly(childContainerName: String)
    case unknown
}

/// Runs the same-file override-membership check for one `@SubContainer`
/// member. The returned enum tells the caller whether to emit the warning,
/// stay silent (child found but has overrideable members), or skip because
/// the child decl is not reachable from this syntax tree.
internal func checkSubContainerChildOverrideMembership(
    for sub: SubContainerMemberModel
) -> SubContainerChildMembership {
    let childTypeName = strippedChildTypeName(from: sub.type)
    guard !childTypeName.isEmpty else {
        return .unknown
    }

    guard let sourceFile = sourceFileSyntax(containing: Syntax(sub.attribute)) else {
        return .unknown
    }

    guard let childDeclGroup = findChildDeclGroup(named: childTypeName, in: sourceFile) else {
        return .unknown
    }

    // Must be a `@DIContainer`. If the author attached `@SubContainer` to a
    // non-container, the existing `sub.*` diagnostics already cover the
    // mismatch at other sites — don't double up here.
    guard declGroupHasDIContainerAttribute(childDeclGroup) else {
        return .unknown
    }

    if declGroupHasOverrideableMember(childDeclGroup) {
        return .hasOverrideableMember
    }
    return .inputOnly(childContainerName: childTypeName)
}

/// Returns the bare nominal name of the child type, stripping attribute
/// wrappers (e.g. `@MainActor`), optional / implicitly-unwrapped wrappers,
/// and module qualifiers — the shape we actually match against decl names
/// in the source file.
///
/// Generic arguments are naturally preserved-then-discarded: a
/// `FeatureContainer<T>` written at the property site is an
/// `IdentifierTypeSyntax` whose `name.text` is `"FeatureContainer"` and whose
/// generic clause is a separate sibling property. We only read `.name.text`,
/// so the returned string for the generic spelling matches the decl's bare
/// name in the source file. No extra stripping needed.
private func strippedChildTypeName(from type: TypeSyntax) -> String {
    var current: TypeSyntax = type

    while true {
        if let attributed = current.as(AttributedTypeSyntax.self) {
            current = attributed.baseType
            continue
        }
        if let optional = current.as(OptionalTypeSyntax.self) {
            current = optional.wrappedType
            continue
        }
        if let iuo = current.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
            current = iuo.wrappedType
            continue
        }
        break
    }

    if let identifier = current.as(IdentifierTypeSyntax.self) {
        return identifier.name.text
    }
    if let member = current.as(MemberTypeSyntax.self) {
        return member.name.text
    }
    return current.trimmedDescription
}

/// Finds a top-level (or nested-top-level) struct / class / actor / enum
/// declaration with `name == childTypeName` inside the file. Only the
/// source file's own statements are scanned — we do not recurse into
/// unrelated types because nested DI containers are rare and would
/// complicate the walk.
private func findChildDeclGroup(
    named childTypeName: String,
    in sourceFile: SourceFileSyntax
) -> (any DeclGroupSyntax)? {
    for statement in sourceFile.statements {
        guard case let .decl(decl) = statement.item else {
            continue
        }
        if let match = matchingDeclGroup(in: decl, named: childTypeName) {
            return match
        }
    }
    return nil
}

private func matchingDeclGroup(
    in decl: DeclSyntax,
    named childTypeName: String
) -> (any DeclGroupSyntax)? {
    if let structDecl = decl.as(StructDeclSyntax.self), structDecl.name.text == childTypeName {
        return structDecl
    }
    if let classDecl = decl.as(ClassDeclSyntax.self), classDecl.name.text == childTypeName {
        return classDecl
    }
    if let actorDecl = decl.as(ActorDeclSyntax.self), actorDecl.name.text == childTypeName {
        return actorDecl
    }
    if let enumDecl = decl.as(EnumDeclSyntax.self), enumDecl.name.text == childTypeName {
        return enumDecl
    }
    return nil
}

private func declGroupHasDIContainerAttribute(_ decl: any DeclGroupSyntax) -> Bool {
    for attributeElement in decl.attributes {
        guard let attribute = attributeElement.as(AttributeSyntax.self) else {
            continue
        }
        if matchesAttributeName(attribute.attributeName, bareName: "DIContainer") {
            return true
        }
    }
    return false
}

private func declGroupHasOverrideableMember(_ decl: any DeclGroupSyntax) -> Bool {
    for member in decl.memberBlock.members {
        guard let variableDecl = member.decl.as(VariableDeclSyntax.self) else {
            continue
        }
        if variableDeclHasOverrideableAttribute(variableDecl) {
            return true
        }
    }
    return false
}

private func variableDeclHasOverrideableAttribute(_ variableDecl: VariableDeclSyntax) -> Bool {
    for attributeElement in variableDecl.attributes {
        guard let attribute = attributeElement.as(AttributeSyntax.self) else {
            continue
        }

        // Any `@SubContainer` child introduces its own `Overrides` slots, so
        // that alone keeps the parent slot well-formed.
        if matchesAttributeName(attribute.attributeName, bareName: "SubContainer") {
            return true
        }

        if matchesAttributeName(attribute.attributeName, bareName: "Provide") {
            if provideAttributeUsesOverrideableScope(attribute) {
                return true
            }
        }
    }
    return false
}

/// Returns `true` unless the `@Provide` attribute explicitly declares
/// `.input`. Unparseable / default scope is conservatively treated as
/// overrideable (defaults to `.shared`) so the warning does not fire on
/// ambiguous input.
private func provideAttributeUsesOverrideableScope(_ attribute: AttributeSyntax) -> Bool {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        // Default scope is `.shared`, which is overrideable.
        return true
    }

    for argument in arguments {
        if argument.label != nil {
            continue
        }
        if let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
            let name = memberAccess.declName.baseName.text
            switch name {
            case "input":
                return false
            case "shared", "transient":
                return true
            default:
                continue
            }
        }
        // First unlabeled argument is the scope. If we can't read it as a
        // MemberAccess, treat as overrideable.
        return true
    }

    // No unlabeled scope argument => default `.shared`.
    return true
}

/// Matches either a bare `IdentifierTypeSyntax` (e.g. `DIContainer`) or a
/// qualified `MemberTypeSyntax` whose leaf name matches `bareName` (e.g.
/// `InnoDI.DIContainer`). This mirrors how `InnoDICore.findAttribute` treats
/// attribute name resolution.
private func matchesAttributeName(_ typeSyntax: TypeSyntax, bareName: String) -> Bool {
    if let identifier = typeSyntax.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == bareName
    }
    if let member = typeSyntax.as(MemberTypeSyntax.self) {
        return member.name.text == bareName
    }
    return false
}
