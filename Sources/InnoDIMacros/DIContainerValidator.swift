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
        let knownNames = Set(model.members.map(\.name))

        for member in model.members {
            let hasFactory = member.factory != nil || member.asyncFactory != nil || member.typeExpr != nil || member.initializer != nil

            if member.factory != nil, member.asyncFactory != nil {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideFactoryConflict())
                )
                hadErrors = true
            }

            if member.scope == .shared && !hasFactory && model.options.validate {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideSharedFactoryRequired())
                )
                hadErrors = true
            }

            if member.scope == .transient && !hasFactory && model.options.validate {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideTransientFactoryRequired())
                )
                hadErrors = true
            }

            if member.scope == .input && hasFactory {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideInputInvalidConfiguration())
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

            if let asyncFactory = member.asyncFactory, !isAsyncClosureExpression(asyncFactory) {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideAsyncFactoryMustBeAsync())
                )
                hadErrors = true
            }

            if member.scope != .input && !member.concreteOptIn && requiresConcreteOptIn(type: member.type) {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(member.attribute),
                        message: SimpleDiagnostic.provideConcreteOptInRequired(
                            name: member.name,
                            typeDescription: member.type.trimmedDescription
                        )
                    )
                )
                hadErrors = true
            }
        }

        if model.options.validateDAG {
            for member in model.members {
                for dependency in member.explicitDependencies where !knownNames.contains(dependency) {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(member.attribute),
                            message: SimpleDiagnostic.containerUnknownDependency(
                                dependencyName: dependency,
                                memberName: member.name
                            )
                        )
                    )
                    hadErrors = true
                }
            }

            var adjacency: [String: [String]] = [:]
            for member in model.members {
                let dependencies = member.graphDependencyCandidates.filter { knownNames.contains($0) }
                adjacency[member.name] = deduplicateStrings(dependencies)
            }

            let cycles = InnoDICore.detectDependencyCycles(adjacency: adjacency)
            if !cycles.isEmpty {
                let memberByName = Dictionary(uniqueKeysWithValues: model.members.map { ($0.name, $0) })
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
        }

        return !hadErrors
    }
}

private func requiresConcreteOptIn(type: TypeSyntax) -> Bool {
    let normalized = normalizedConcreteCheckType(type)

    if normalized.is(SomeOrAnyTypeSyntax.self) || normalized.is(CompositionTypeSyntax.self) {
        return false
    }

    if let identifier = normalized.as(IdentifierTypeSyntax.self) {
        return !isExistentialIdentifier(identifier.name.text)
    }

    if let member = normalized.as(MemberTypeSyntax.self) {
        return !isExistentialIdentifier(member.name.text)
    }

    return true
}

private func normalizedConcreteCheckType(_ type: TypeSyntax) -> TypeSyntax {
    if let optional = type.as(OptionalTypeSyntax.self) {
        return normalizedConcreteCheckType(optional.wrappedType)
    }

    if let implicitlyUnwrapped = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
        return normalizedConcreteCheckType(implicitlyUnwrapped.wrappedType)
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedConcreteCheckType(attributed.baseType)
    }

    if let tuple = type.as(TupleTypeSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.firstName == nil,
       first.secondName == nil {
        return normalizedConcreteCheckType(first.type)
    }

    if let identifier = type.as(IdentifierTypeSyntax.self),
       identifier.name.text == "Optional",
       let wrapped = identifier.genericArgumentClause?.arguments.first?.argument,
       let wrappedType = wrapped.as(TypeSyntax.self) {
        return normalizedConcreteCheckType(wrappedType)
    }

    return type
}

private func isExistentialIdentifier(_ name: String) -> Bool {
    name == "Any" || name == "AnyObject"
}

private func isAsyncClosureExpression(_ expr: ExprSyntax) -> Bool {
    guard let closure = expr.as(ClosureExprSyntax.self) else {
        return false
    }
    return closure.signature?.effectSpecifiers?.asyncSpecifier != nil
}
