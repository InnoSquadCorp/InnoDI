import InnoDICore
import SwiftSyntax

func extractWithDependencyReferences(
    from attribute: AttributeSyntax,
    requiringCanonicalProvidePath: Bool = false
) -> [WithDependencyReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments {
        guard let label = argument.label?.text else { continue }
        switch label {
        case "with":
            guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else { continue }
            return arrayExpr.elements.compactMap { element in
                guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
                      !requiringCanonicalProvidePath
                        || (
                            keyPath.root?.trimmedDescription == "Self"
                                && keyPath.components.count == 1
                        ),
                      let property = keyPath.components.last?
                        .component.as(KeyPathPropertyComponentSyntax.self)?
                        .declName.baseName.text else {
                    return nil
                }
                return WithDependencyReference(
                    name: property,
                    anchorExpression: ExprSyntax(keyPath)
                )
            }
        default:
            continue
        }
    }

    return []
}

func extractMultibindingDependencyReferences(
    from attribute: AttributeSyntax
) -> [WithDependencyReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          arguments.count == 1,
          let argument = arguments.first,
          argument.label == nil,
          let array = argument.expression.as(ArrayExprSyntax.self) else {
        return []
    }
    return array.elements.compactMap { element in
        guard let keyPath = element.expression.as(KeyPathExprSyntax.self),
              keyPath.root?.trimmedDescription == "Self",
              keyPath.components.count == 1,
              let property = keyPath.components.last?
                .component.as(KeyPathPropertyComponentSyntax.self)?
                .declName.baseName.text else {
            return nil
        }
        return WithDependencyReference(
            name: property,
            anchorExpression: ExprSyntax(keyPath)
        )
    }
}

func sameNameWiringExpressionSyntax(
    for state: SubContainerSameNameWiringParseState,
    in attribute: AttributeSyntax
) -> ExprSyntax? {
    switch state {
    case .omitted:
        return nil
    case let .parsed(label, _), let .invalid(label):
        return extractArgumentExpression(label: label.rawValue, from: attribute)
    }
}

func extractSubContainerBindingReferences(
    from attribute: AttributeSyntax
) -> [SubContainerBindingReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "bindings" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return []
        }

        return arrayExpr.elements.compactMap { element in
            guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                return nil
            }

            var childName: String?
            var parentName: String?
            var childKeyPath: KeyPathExprSyntax?
            var parentKeyPath: KeyPathExprSyntax?

            for tupleElement in tupleExpr.elements {
                guard let label = tupleElement.label?.text,
                      let keyPath = tupleElement.expression.as(KeyPathExprSyntax.self),
                      let property = keyPath.components.last?
                        .component.as(KeyPathPropertyComponentSyntax.self)?
                        .declName.baseName.text else {
                    continue
                }

                switch label {
                case "child":
                    childName = property
                    childKeyPath = keyPath
                case "parent":
                    parentName = property
                    parentKeyPath = keyPath
                default:
                    continue
                }
            }

            guard let childName, let parentName, let childKeyPath, let parentKeyPath else {
                return nil
            }

            return SubContainerBindingReference(
                childInputName: childName,
                parentMemberName: parentName,
                childKeyPath: childKeyPath,
                parentKeyPath: parentKeyPath
            )
        }
    }

    return []
}

func extractInvalidSubContainerBindingReferences(
    from attribute: AttributeSyntax
) -> [InvalidSubContainerBindingReference] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    for argument in arguments where argument.label?.text == "bindings" {
        guard let arrayExpr = argument.expression.as(ArrayExprSyntax.self) else {
            return [
                InvalidSubContainerBindingReference(anchorExpression: argument.expression)
            ]
        }

        var invalidReferences: [InvalidSubContainerBindingReference] = []
        for element in arrayExpr.elements {
            guard let tupleExpr = element.expression.as(TupleExprSyntax.self) else {
                invalidReferences.append(
                    InvalidSubContainerBindingReference(anchorExpression: element.expression)
                )
                continue
            }

            var hasChild = false
            var hasParent = false
            var elementIsInvalid = false

            for tupleElement in tupleExpr.elements {
                guard let label = tupleElement.label?.text else { continue }
                switch label {
                case "child", "parent":
                    guard finalKeyPathExpression(tupleElement.expression) != nil else {
                        elementIsInvalid = true
                        continue
                    }
                    if label == "child" {
                        hasChild = true
                    } else {
                        hasParent = true
                    }
                default:
                    continue
                }
            }

            if elementIsInvalid || !hasChild || !hasParent {
                invalidReferences.append(
                    InvalidSubContainerBindingReference(anchorExpression: element.expression)
                )
            }
        }
        return invalidReferences
    }

    return []
}

private func finalKeyPathExpression(
    _ expression: ExprSyntax
) -> KeyPathExprSyntax? {
    guard let keyPath = expression.as(KeyPathExprSyntax.self),
          keyPath.components.last?
            .component.as(KeyPathPropertyComponentSyntax.self)?
            .declName.baseName.text != nil else {
        return nil
    }
    return keyPath
}
