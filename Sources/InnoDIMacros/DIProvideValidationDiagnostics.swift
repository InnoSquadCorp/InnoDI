//
//  DIProvideValidationDiagnostics.swift
//  InnoDIMacros
//
//  Houses every `SimpleDiagnostic` / `SimpleNote` / `FixIt` constructor the
//  validator's top-level `validate(model:context:)` reaches for. The split
//  keeps the validation loop itself focused on ordering checks while making
//  diagnostic message / fix-it logic easier to extend.
//

import InnoDICore
import SwiftDiagnostics
import SwiftSyntax

internal func makeUnresolvedFactoryParameterDiagnostic(
    member: ProvideMemberModel,
    dependencyName: String,
    resolutionContext: DependencyResolutionContext,
    memberIndex: Int
) -> Diagnostic {
    let reference = member.closureParameterReferences.first(where: { $0.name == dependencyName })
    let node = reference.map { Syntax($0.token) } ?? Syntax(member.attribute)
    let candidates = matchingDependencyCandidates(
        for: dependencyName,
        resolutionContext: resolutionContext,
        memberIndex: memberIndex
    )
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
    if !candidates.available.isEmpty {
        notes.append(
            Note(
                node: Syntax(member.attribute),
                message: SimpleNote(
                    "Closest injectable member candidate: \(candidates.available.joined(separator: ", ")).",
                    code: .provideUnresolvedFactoryParameter,
                    suffix: "candidate"
                )
            )
        )
    } else if !candidates.unavailable.isEmpty {
        notes.append(
            Note(
                node: Syntax(member.attribute),
                message: SimpleNote(
                    "Closest matching member exists, but declaration order still makes it unavailable here: \(candidates.unavailable.joined(separator: ", ")).",
                    code: .provideUnresolvedFactoryParameter,
                    suffix: "candidate-unavailable"
                )
            )
        )
    } else {
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
    }

    let fixIts = makeRenameTokenFixIts(
        token: reference?.token,
        replacementCandidates: candidates.available,
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

internal struct DirectProviderEagerCallSite {
    let providerName: String
    let node: Syntax
}

internal func collectDirectProviderEagerCalls(
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

internal func makeUnresolvedWithDependencyDiagnostic(
    member: ProvideMemberModel,
    dependencyName: String,
    resolutionContext: DependencyResolutionContext,
    memberIndex: Int
) -> Diagnostic {
    let reference = member.withDependencyReferences.first(where: { $0.name == dependencyName })
    let node = reference.map { Syntax($0.anchorExpression) } ?? Syntax(member.attribute)
    let candidates = matchingDependencyCandidates(
        for: dependencyName,
        resolutionContext: resolutionContext,
        memberIndex: memberIndex
    )
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
    if !candidates.available.isEmpty {
        notes.append(
            Note(
                node: Syntax(member.attribute),
                message: SimpleNote(
                    "Closest injectable member candidate: \(candidates.available.joined(separator: ", ")).",
                    code: .provideUnresolvedWithDependency,
                    suffix: "candidate"
                )
            )
        )
    } else if !candidates.unavailable.isEmpty {
        notes.append(
            Note(
                node: Syntax(member.attribute),
                message: SimpleNote(
                    "Closest matching member exists, but declaration order still makes it unavailable here: \(candidates.unavailable.joined(separator: ", ")).",
                    code: .provideUnresolvedWithDependency,
                    suffix: "candidate-unavailable"
                )
            )
        )
    } else {
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
    }

    let fixIts = makeReplaceSyntaxTextFixIts(
        syntax: reference.map { Syntax($0.anchorExpression) },
        replacementCandidates: candidates.available.map { "\\.\($0)" },
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

internal func makeUnavailableDependencyDiagnostic(
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

internal func makeConcreteOptInDiagnostic(member: ProvideMemberModel) -> Diagnostic {
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
    knownNames
        .filter { normalizedDependencyLookupKey($0) == normalizedDependencyLookupKey(dependencyName) }
        .sorted()
}

private struct MatchingDependencyCandidates {
    let available: [String]
    let unavailable: [String]
}

private func matchingDependencyCandidates(
    for dependencyName: String,
    resolutionContext: DependencyResolutionContext,
    memberIndex: Int
) -> MatchingDependencyCandidates {
    let matches = matchingDependencyCandidates(for: dependencyName, in: resolutionContext.knownNames)
    let available = matches.filter {
        resolutionContext.status(of: $0, forMemberAt: memberIndex) == .available
    }
    let unavailable = matches.filter {
        resolutionContext.status(of: $0, forMemberAt: memberIndex) == .unavailable
    }
    return MatchingDependencyCandidates(available: available, unavailable: unavailable)
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
