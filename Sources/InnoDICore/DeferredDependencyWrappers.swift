import SwiftSyntax

package enum DeferredDependencyWrapperKind: String {
    case lazy = "Lazy"
    case provider = "Provider"
}

/// Construction-edge classification shared by macro generation planning and
/// dependency-graph collection.
///
/// Keeping this syntax-derived record in Core is intentional: the compiler
/// macro and the build-time graph must agree on whether one factory parameter
/// is eager, lazy, or provider-backed before either layer applies its own
/// availability or container-resolution policy.
package enum FactoryDependencyKind: String, Equatable, Hashable, Sendable {
    case hard
    case lazy
    case provider
}

/// One named factory parameter after wrapper normalization.
package struct FactoryDependencyReference: Equatable, Hashable, Sendable {
    package let name: String
    package let kind: FactoryDependencyKind

    /// Normalized referenced type when the syntax has a nominal shape.
    /// Deferred wrappers expose their wrapped type; hard parameters expose
    /// their declared type. Callers that only need ordering may ignore it.
    package let targetReference: SemanticTypeReference?

    package init(
        name: String,
        kind: FactoryDependencyKind,
        targetReference: SemanticTypeReference?
    ) {
        self.name = name
        self.kind = kind
        self.targetReference = targetReference
    }
}

/// Parses the dependency parameters of one managed factory closure.
///
/// - Returns: `nil` when `expression` is not a closure, otherwise the ordered
///   dependency records. Wildcard parameters are omitted because they cannot
///   name a generated dependency edge.
package func managedFactoryDependencyReferences(
    in expression: ExprSyntax
) -> [FactoryDependencyReference]? {
    guard let closure = expression.as(ClosureExprSyntax.self) else {
        return nil
    }
    guard let parameterClause = closure.signature?.parameterClause else {
        return []
    }

    switch parameterClause {
    case .simpleInput(let parameters):
        return parameters.compactMap { parameter in
            let name = parameter.name.text
            guard name != "_" else { return nil }
            return FactoryDependencyReference(
                name: name,
                kind: .hard,
                targetReference: nil
            )
        }
    case .parameterClause(let clause):
        return clause.parameters.compactMap { parameter in
            let token = parameter.secondName ?? parameter.firstName
            let name = token.text
            guard name != "_" else { return nil }

            let kind: FactoryDependencyKind
            let targetReference: SemanticTypeReference?
            switch deferredDependencyWrapperKind(for: parameter.type) {
            case .lazy:
                kind = .lazy
                targetReference = deferredDependencyWrappedTypeReference(
                    parameter.type
                )
            case .provider:
                kind = .provider
                targetReference = deferredDependencyWrappedTypeReference(
                    parameter.type
                )
            case .none:
                kind = .hard
                if let type = parameter.type {
                    targetReference = normalizedSemanticTypeReference(type)
                } else {
                    targetReference = nil
                }
            }
            return FactoryDependencyReference(
                name: name,
                kind: kind,
                targetReference: targetReference
            )
        }
    }
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
    // Intentionally does not unwrap `T?`, `T!`, or `Optional<T>` so optional
    // deferred wrappers like `Lazy<T>?` are not silently treated as supported.
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
