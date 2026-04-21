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

        for (index, member) in model.members.enumerated() {
            let hasFactory = member.factory != nil || member.asyncFactory != nil || member.typeExpr != nil || member.initializer != nil
            let hasInputConfiguration = hasFactory || !member.withDependencies.isEmpty

            if member.factory != nil, member.asyncFactory != nil {
                context.diagnose(
                    Diagnostic(node: Syntax(member.attribute), message: SimpleDiagnostic.provideFactoryConflict())
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
                    makeConcreteOptInDiagnostic(member: member)
                )
                hadErrors = true
            }

            let hardClosureNames = Set(member.hardClosureDependencies)
            let softClosureReferences = Dictionary(uniqueKeysWithValues: member.softClosureParameterReferences.map { ($0.name, $0) })
            let providerClosureReferences = Dictionary(uniqueKeysWithValues: member.providerClosureParameterReferences.map { ($0.name, $0) })

            if member.scope == .shared {
                let providerNames = Set(providerClosureReferences.keys)
                if !providerNames.isEmpty {
                    let sharedClosures = [member.factory, member.asyncFactory].compactMap { $0?.as(ClosureExprSyntax.self) }
                    for closure in sharedClosures {
                        for callSite in collectDirectProviderEagerCalls(in: closure, providerNames: providerNames) {
                            context.diagnose(
                                Diagnostic(
                                    node: callSite.node,
                                    message: SimpleDiagnostic.provideProviderEagerCall(
                                        memberName: member.name,
                                        dependencyName: callSite.providerName
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

                let status = resolutionContext.status(of: dependency, forMemberAt: index)
                switch status {
                case .available:
                    break
                case .unknown:
                    context.diagnose(
                        makeUnresolvedFactoryParameterDiagnostic(
                            member: member,
                            dependencyName: dependency,
                            knownNames: resolutionContext.knownNames
                        )
                    )
                    hadErrors = true
                case .unavailable:
                    // Soft (Lazy<T>) and provider (Provider<T>) edges
                    // intentionally escape declaration-order availability: the
                    // runtime `_LazyCell` box lets a forward reference resolve
                    // safely once init completes, and `Provider<T>` reaches
                    // its transient target through the same late-binding
                    // resolver. Only hard edges still need to be reachable in
                    // declaration order.
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
                let referencedMember = memberByName[dependency]
                switch resolutionContext.status(of: dependency, forMemberAt: index) {
                case .available:
                    break
                case .unknown:
                    context.diagnose(
                        makeUnresolvedWithDependencyDiagnostic(
                            member: member,
                            dependencyName: dependency,
                            knownNames: resolutionContext.knownNames
                        )
                    )
                    hadErrors = true
                case .unavailable:
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

            for dependency in deduplicateStrings(member.expressionReferences) where resolutionContext.knownNames.contains(dependency) {
                let referencedMember = memberByName[dependency]
                if resolutionContext.status(of: dependency, forMemberAt: index) == .unavailable {
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

        if model.options.validateDAG {
            var adjacency: [String: [String]] = [:]
            for index in model.members.indices {
                let member = model.members[index]
                // Exclude deferred edges (`Lazy<T>` / `Provider<T>`) from
                // cycle detection so intentionally-broken graphs compile
                // cleanly. The corresponding hard-only graph still
                // participates in declaration-order availability checks via
                // status(…).
                let dependencies = resolutionContext.hardGraphDependencies(forMemberAt: index)
                adjacency[member.name] = deduplicateStrings(dependencies)
            }

            let cycles = InnoDICore.detectDependencyCycles(adjacency: adjacency)
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
        }

        // Phase M — sub-container validation.
        //
        // The parser has already rejected properties carrying both
        // `@Provide` and `@SubContainer` (see `sub.conflicts-with-provide`
        // in `DIContainerParser`). We still need to check:
        //   - scope argument presence and spelling
        //   - `with:` keypaths reference real parent members
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

            if !sub.parentDependencies.isEmpty && !sub.explicitBindings.isEmpty {
                context.diagnose(
                    Diagnostic(
                        node: Syntax(sub.attribute),
                        message: SimpleDiagnostic.subBindingsConflictsWithWith(memberName: sub.name)
                    )
                )
                hadErrors = true
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

            // `with:` keypaths must resolve to @Provide members on the parent.
            for parentName in sub.parentDependencies {
                if !knownParentMemberNames.contains(parentName) {
                    context.diagnose(
                        Diagnostic(
                            node: sub.parentKeyPathSyntax(for: parentName).map(Syntax.init) ?? Syntax(sub.attribute),
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

            // `.shared` sub-containers read parent members through private
            // `_storage_<name>` at init time, so `.transient` parents are
            // off-limits (no storage slot exists for them). When the author
            // relies on auto-matching we walk every parent member; with an
            // explicit `with:` list we check only those.
            guard sub.scope == .shared else { continue }
            let wiredParents: [String]
            if !sub.explicitBindings.isEmpty {
                wiredParents = sub.explicitBindings.map(\.parentMemberName)
            } else if sub.parentDependencies.isEmpty {
                wiredParents = model.members.map(\.name)
            } else {
                wiredParents = sub.parentDependencies
            }
            for parentName in wiredParents where knownParentMemberNames.contains(parentName) {
                if memberScopeByName[parentName] == .transient {
                    let diagnosticNode = sub.parentBindingKeyPathSyntax(for: parentName).map(Syntax.init)
                        ?? sub.parentKeyPathSyntax(for: parentName).map(Syntax.init)
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

        return !hadErrors
    }
}

private func makeUnresolvedFactoryParameterDiagnostic(
    member: ProvideMemberModel,
    dependencyName: String,
    knownNames: Set<String>
    ) -> Diagnostic {
    let reference = member.closureParameterReferences.first(where: { $0.name == dependencyName })
    let node = reference.map { Syntax($0.token) } ?? Syntax(member.attribute)
    let candidates = matchingDependencyCandidates(for: dependencyName, in: knownNames)
    var notes = [
        Note(
            node: Syntax(member.attribute),
            message: SimpleNote(
                "Rename the factory parameter to match an injectable member name, or switch to explicit wiring inside the factory body.",
                code: .provideUnresolvedFactoryParameter,
                suffix: "resolution"
            )
        )
    ]
    if candidates.isEmpty {
        notes.append(
            Note(
                node: Syntax(member.bindingSyntax),
                message: SimpleNote(
                    "'\(member.name)' can only inject members declared in the container by exact member name.",
                    code: .provideUnresolvedFactoryParameter,
                    suffix: "member-scope"
                )
            )
        )
    } else {
        notes.append(
            Note(
                node: Syntax(member.attribute),
                message: SimpleNote(
                    "Closest injectable member candidate: \(candidates.joined(separator: ", ")).",
                    code: .provideUnresolvedFactoryParameter,
                    suffix: "candidate"
                )
            )
        )
    }

    let fixIts = makeRenameTokenFixIts(
        token: reference?.token,
        replacementCandidates: candidates,
        code: .provideUnresolvedFactoryParameter,
        label: "Rename parameter"
    )

    return Diagnostic(
        node: node,
        message: SimpleDiagnostic.provideUnresolvedFactoryParameter(
            memberName: member.name,
            parameterName: dependencyName
        ),
        notes: notes,
        fixIts: fixIts
    )
}

private struct DirectProviderEagerCallSite {
    let providerName: String
    let node: Syntax
}

private func collectDirectProviderEagerCalls(
    in closure: ClosureExprSyntax,
    providerNames: Set<String>
) -> [DirectProviderEagerCallSite] {
    guard !providerNames.isEmpty else { return [] }

    var callSites: [DirectProviderEagerCallSite] = []

    func walk(node: Syntax) {
        if node.is(ClosureExprSyntax.self)
            || node.is(FunctionDeclSyntax.self)
            || node.is(InitializerDeclSyntax.self) {
            return
        }

        if let functionCall = node.as(FunctionCallExprSyntax.self),
           let callSite = directProviderEagerCallSite(in: functionCall, providerNames: providerNames) {
            callSites.append(callSite)
        }

        for child in node.children(viewMode: .sourceAccurate) {
            walk(node: child)
        }
    }

    for statement in closure.statements {
        walk(node: Syntax(statement.item))
    }

    return callSites
}

private func directProviderEagerCallSite(
    in functionCall: FunctionCallExprSyntax,
    providerNames: Set<String>
) -> DirectProviderEagerCallSite? {
    let calledExpression = unwrapProviderCallExpression(functionCall.calledExpression)

    if let reference = calledExpression.as(DeclReferenceExprSyntax.self),
       providerNames.contains(reference.baseName.text) {
        return DirectProviderEagerCallSite(
            providerName: reference.baseName.text,
            node: Syntax(reference)
        )
    }

    if let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
       let base = unwrapProviderCallBase(memberAccess.base),
       providerNames.contains(base.baseName.text),
       ["callAsFunction", "resolver"].contains(memberAccess.declName.baseName.text) {
        return DirectProviderEagerCallSite(
            providerName: base.baseName.text,
            node: Syntax(memberAccess)
        )
    }

    return nil
}

private func unwrapProviderCallExpression(_ expression: ExprSyntax) -> ExprSyntax {
    if let tuple = expression.as(TupleExprSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.label == nil {
        return unwrapProviderCallExpression(first.expression)
    }

    return expression
}

private func unwrapProviderCallBase(_ expression: ExprSyntax?) -> DeclReferenceExprSyntax? {
    guard let expression else { return nil }

    let unwrapped = unwrapProviderCallExpression(expression)
    return unwrapped.as(DeclReferenceExprSyntax.self)
}

private func makeUnresolvedWithDependencyDiagnostic(
    member: ProvideMemberModel,
    dependencyName: String,
    knownNames: Set<String>
) -> Diagnostic {
    let reference = member.withDependencyReferences.first(where: { $0.name == dependencyName })
    let node = reference.map { Syntax($0.keyPath) } ?? Syntax(member.attribute)
    let candidates = matchingDependencyCandidates(for: dependencyName, in: knownNames)
    var notes = [
        Note(
            node: Syntax(member.attribute),
            message: SimpleNote(
                "Use a key path that points to an injectable container member, or replace this with an explicit factory closure.",
                code: .provideUnresolvedWithDependency,
                suffix: "resolution"
            )
        )
    ]
    if candidates.isEmpty {
        notes.append(
            Note(
                node: Syntax(member.bindingSyntax),
                message: SimpleNote(
                    "'\(member.name)' can only autowire key paths that map to container member names.",
                    code: .provideUnresolvedWithDependency,
                    suffix: "member-scope"
                )
            )
        )
    } else {
        notes.append(
            Note(
                node: Syntax(member.attribute),
                message: SimpleNote(
                    "Closest injectable member candidate: \(candidates.joined(separator: ", ")).",
                    code: .provideUnresolvedWithDependency,
                    suffix: "candidate"
                )
            )
        )
    }

    let fixIts = makeReplaceSyntaxTextFixIts(
        syntax: reference.map { Syntax($0.keyPath) },
        replacementCandidates: candidates.map { "\\.\($0)" },
        code: .provideUnresolvedWithDependency,
        label: "Replace key path"
    )

    return Diagnostic(
        node: node,
        message: SimpleDiagnostic.provideUnresolvedWithDependency(
            memberName: member.name,
            dependencyName: dependencyName
        ),
        notes: notes,
        fixIts: fixIts
    )
}

private func makeUnavailableDependencyDiagnostic(
    member: ProvideMemberModel,
    dependencyName: String,
    referencedMember: ProvideMemberModel?
) -> Diagnostic {
    var notes = [
        Note(
            node: Syntax(member.attribute),
            message: SimpleNote(
                "Shared members can only reference inputs and dependencies that are already available in declaration order. Transient members can reference any container member.",
                code: .provideUnavailableDependencyReference,
                suffix: "declaration-order"
            )
        )
    ]

    if let referencedMember {
        notes.append(
            Note(
                node: Syntax(referencedMember.bindingSyntax),
                message: SimpleNote(
                    "'\(dependencyName)' is declared here.",
                    code: .provideUnavailableDependencyReference,
                    suffix: "declaration-site"
                )
            )
        )
    } else {
        notes.append(
            Note(
                node: Syntax(member.bindingSyntax),
                message: SimpleNote(
                    "Declare '\(dependencyName)' before '\(member.name)', or switch to explicit transient/manual wiring if declaration order cannot change.",
                    code: .provideUnavailableDependencyReference,
                    suffix: "resolution"
                )
            )
        )
    }

    return Diagnostic(
        node: Syntax(member.attribute),
        message: SimpleDiagnostic.provideUnavailableDependencyReference(
            memberName: member.name,
            dependencyName: dependencyName
        ),
        notes: notes
    )
}

private func makeConcreteOptInDiagnostic(member: ProvideMemberModel) -> Diagnostic {
    let notes = [
        Note(
            node: Syntax(member.attribute),
            message: SimpleNote(
                "If this dependency must remain a concrete type, opt in explicitly with concrete: true.",
                code: .provideConcreteOptInRequired,
                suffix: "opt-in"
            )
        ),
        Note(
            node: Syntax(member.bindingSyntax),
            message: SimpleNote(
                "If protocol-first wiring is possible, prefer changing the property type to an existential such as any Protocol.",
                code: .provideConcreteOptInRequired,
                suffix: "protocol-first"
            )
        )
    ]

    return Diagnostic(
        node: Syntax(member.attribute),
        message: SimpleDiagnostic.provideConcreteOptInRequired(
            name: member.name,
            typeDescription: member.type.trimmedDescription
        ),
        notes: notes,
        fixIts: makeConcreteOptInFixIts(attribute: member.attribute)
    )
}

private func matchingDependencyCandidates(for dependencyName: String, in knownNames: Set<String>) -> [String] {
    let normalizedTarget = normalizedDependencyLookupKey(dependencyName)
    return knownNames
        .filter { normalizedDependencyLookupKey($0) == normalizedTarget }
        .sorted()
}

private func normalizedDependencyLookupKey(_ name: String) -> String {
    name
        .filter { $0 != "_" }
        .lowercased()
}

private func makeRenameTokenFixIts(
    token: TokenSyntax?,
    replacementCandidates: [String],
    code: InnoDIDiagnosticCode,
    label: String
) -> [FixIt] {
    guard let token, replacementCandidates.count == 1 else {
        return []
    }

    let replacement = replacementCandidates[0]
    return [
        FixIt(
            message: SimpleFixIt("\(label) to '\(replacement)'", code: code, suffix: "rename"),
            changes: [
                .replaceText(
                    range: token.positionAfterSkippingLeadingTrivia..<token.endPositionBeforeTrailingTrivia,
                    with: replacement,
                    in: Syntax(token.root)
                )
            ]
        )
    ]
}

private func makeConcreteOptInFixIts(attribute: AttributeSyntax) -> [FixIt] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self) else {
        return []
    }

    let replacement: String
    if arguments.isEmpty {
        replacement = "concrete: true"
    } else if arguments.contains(where: { $0.label?.text == "concrete" }) {
        return []
    } else {
        replacement = ", concrete: true"
    }

    let insertionPosition = arguments.endPositionBeforeTrailingTrivia

    return [
        FixIt(
            message: SimpleFixIt("Add concrete: true", code: .provideConcreteOptInRequired, suffix: "insert-concrete"),
            changes: [
                .replaceText(
                    range: insertionPosition..<insertionPosition,
                    with: replacement,
                    in: Syntax(attribute.root)
                )
            ]
        )
    ]
}

private func makeReplaceSyntaxTextFixIts(
    syntax: Syntax?,
    replacementCandidates: [String],
    code: InnoDIDiagnosticCode,
    label: String
) -> [FixIt] {
    guard let syntax, replacementCandidates.count == 1 else {
        return []
    }

    let replacement = replacementCandidates[0]
    return [
        FixIt(
            message: SimpleFixIt("\(label) with '\(replacement)'", code: code, suffix: "replace"),
            changes: [
                .replaceText(
                    range: syntax.positionAfterSkippingLeadingTrivia..<syntax.endPositionBeforeTrailingTrivia,
                    with: replacement,
                    in: Syntax(syntax.root)
                )
            ]
        )
    ]
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
