import SwiftSyntax

package enum DeferredDependencyWrapperKind: String {
    case lazy = "Lazy"
    case provider = "Provider"
}

package func deferredDependencyWrapperKind(for type: TypeSyntax?) -> DeferredDependencyWrapperKind? {
    guard let type else { return nil }

    let normalized = unwrapDeferredDependencyWrapperType(type)

    if let identifier = normalized.as(IdentifierTypeSyntax.self) {
        guard identifier.genericArgumentClause?.arguments.count == 1 else {
            return nil
        }
        return DeferredDependencyWrapperKind(rawValue: identifier.name.text)
    }

    if let member = normalized.as(MemberTypeSyntax.self) {
        guard member.genericArgumentClause?.arguments.count == 1 else {
            return nil
        }
        return DeferredDependencyWrapperKind(rawValue: member.name.text)
    }

    return nil
}

package func deferredDependencyWrapperCalleeDescription(
    for type: TypeSyntax?,
    kind: DeferredDependencyWrapperKind
) -> String? {
    guard deferredDependencyWrapperKind(for: type) == kind,
          let type else {
        return nil
    }

    let normalized = unwrapDeferredDependencyWrapperType(type)

    if normalized.is(IdentifierTypeSyntax.self) {
        return kind.rawValue
    }

    if let member = normalized.as(MemberTypeSyntax.self) {
        return "\(unwrapDeferredDependencyWrapperType(member.baseType).trimmedDescription).\(kind.rawValue)"
    }

    return nil
}

package func deferredDependencyWrappedTypeReference(_ type: TypeSyntax?) -> SemanticTypeReference? {
    guard let type else { return nil }

    let normalized = unwrapDeferredDependencyWrapperType(type)

    if let identifier = normalized.as(IdentifierTypeSyntax.self),
       let argument = identifier.genericArgumentClause?.arguments.first?.argument,
       let wrappedType = argument.as(TypeSyntax.self) {
        return normalizedSemanticTypeReference(wrappedType)
    }

    if let member = normalized.as(MemberTypeSyntax.self),
       let argument = member.genericArgumentClause?.arguments.first?.argument,
       let wrappedType = argument.as(TypeSyntax.self) {
        return normalizedSemanticTypeReference(wrappedType)
    }

    return nil
}

private func unwrapDeferredDependencyWrapperType(_ type: TypeSyntax) -> TypeSyntax {
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return unwrapDeferredDependencyWrapperType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return unwrapDeferredDependencyWrapperType(first.type)
    }
    return type
}
