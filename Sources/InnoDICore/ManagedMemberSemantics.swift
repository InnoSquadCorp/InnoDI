import SwiftSyntax

/// The mutually exclusive semantic roles supported for a direct member of an
/// `@DIContainer` declaration.
///
/// The syntax anchor stays attached to the parsed arguments so macro
/// diagnostics can remain source-precise while build validators consume the
/// same classification and argument semantics.
package enum ManagedMemberRole {
    case provide(attribute: AttributeSyntax, arguments: ProvideArguments)
    case subContainer(
        attribute: AttributeSyntax,
        arguments: SubContainerAttributeInfo
    )
}

/// Shared first-stage IR for `@Provide` / `@SubContainer` member attributes.
///
/// This type owns role matching, duplicate counts, role conflicts, and the
/// parsed argument model for a unique role. Consumers still own diagnostics
/// and declaration-shape policy because those differ between an attached
/// macro and a whole-workspace validator.
package struct ManagedMemberSemantics {
    package let provideAttributes: [AttributeSyntax]
    package let subContainerAttributes: [AttributeSyntax]

    package var hasAnyRole: Bool {
        !provideAttributes.isEmpty || !subContainerAttributes.isEmpty
    }

    package var hasExactlyOneRole: Bool {
        (provideAttributes.count == 1 && subContainerAttributes.isEmpty)
            || (subContainerAttributes.count == 1
                && provideAttributes.isEmpty)
    }

    package var hasConflictingRoles: Bool {
        !provideAttributes.isEmpty && !subContainerAttributes.isEmpty
    }

    /// Parses arguments only when a consumer asks for the unique semantic
    /// role. Whole-workspace collectors that only need attribute anchors do
    /// not pay for argument parsing.
    package var uniqueRole: ManagedMemberRole? {
        if provideAttributes.count == 1,
           subContainerAttributes.isEmpty,
           let attribute = provideAttributes.first {
            return .provide(
                attribute: attribute,
                arguments: parseProvideArguments(attribute)
            )
        }
        if subContainerAttributes.count == 1,
           provideAttributes.isEmpty,
           let attribute = subContainerAttributes.first {
            return .subContainer(
                attribute: attribute,
                arguments: parseSubContainerArguments(attribute)
            )
        }
        return nil
    }

    package var provideArguments: ProvideArguments? {
        guard case let .provide(_, arguments) = uniqueRole else {
            return nil
        }
        return arguments
    }

    package var subContainerArguments: SubContainerAttributeInfo? {
        guard case let .subContainer(_, arguments) = uniqueRole else {
            return nil
        }
        return arguments
    }

    package init(attributes: AttributeListSyntax?) {
        let attributes = attributes ?? []
        provideAttributes = attributes.compactMap { element in
            guard let attribute = element.as(AttributeSyntax.self),
                  matchesInnoDIAttribute(
                    named: "Provide",
                    attributeName: attribute.attributeName
                  ) else {
                return nil
            }
            return attribute
        }
        subContainerAttributes = attributes.compactMap { element in
            guard let attribute = element.as(AttributeSyntax.self),
                  matchesInnoDIAttribute(
                    named: "SubContainer",
                    attributeName: attribute.attributeName
                  ) else {
                return nil
            }
            return attribute
        }
    }
}

package func parseManagedMemberSemantics(
    _ attributes: AttributeListSyntax?
) -> ManagedMemberSemantics {
    ManagedMemberSemantics(attributes: attributes)
}
