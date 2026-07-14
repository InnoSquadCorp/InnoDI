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
import SwiftSyntaxMacros

/// Diagnoses hard dependency edges whose provider requires more effects than
/// the consumer explicitly declares. This validation is intentionally
/// independent of DAG validation: disabling cycle/order checks must never let
/// generated accessors or `Task` failure types become ill-formed Swift.
///
/// Deferred `Lazy<T>` and `Provider<T>` edges are excluded here. Their public
/// contract is synchronous and the validator reports their dedicated target
/// diagnostics instead.
internal func diagnoseIncompatibleDependencyEffects(
    member: ProvideMemberModel,
    memberByName: [String: ProvideMemberModel],
    context: some MacroExpansionContext
) -> Set<String> {
    guard member.scope != .input,
          member.hasLocallyValidConstructionConfiguration,
          member.factory == nil || member.asyncFactory == nil else {
        return []
    }

    let closureReferences: [(name: String, node: Syntax)] = member.closureParameterReferences
        .filter { $0.kind == .hard }
        .map { (name: $0.name, node: Syntax($0.token)) }

    var seenNames: Set<String> = []
    var diagnosedNames: Set<String> = []
    for reference in closureReferences where seenNames.insert(reference.name).inserted {
        guard let provider = memberByName[reference.name],
              provider.hasLocallyValidConstructionConfiguration,
              let mismatch = dependencyEffectMismatch(
                  consumer: member.constructionEffect,
                  provider: provider.constructionEffect
              ) else {
            continue
        }

        diagnosedNames.insert(reference.name)

        let message: SimpleDiagnostic
        switch mismatch {
        case let .requiresAsync(providerThrows):
            message = .provideAsyncDependencyRequiresAsyncConsumer(
                memberName: member.name,
                dependencyName: reference.name,
                providerThrows: providerThrows
            )
        case .requiresThrowing:
            message = .provideThrowingDependencyRequiresThrowingConsumer(
                memberName: member.name,
                dependencyName: reference.name
            )
        }
        context.diagnose(Diagnostic(node: reference.node, message: message))
    }

    for reference in member.withDependencyReferences
        where seenNames.insert(reference.name).inserted {
        guard let provider = memberByName[reference.name],
              provider.hasLocallyValidConstructionConfiguration else {
            continue
        }
        let providerThrows: Bool
        switch provider.constructionEffect {
        case .synchronous:
            continue
        case .asynchronous:
            providerThrows = false
        case .asynchronousThrowing:
            providerThrows = true
        }

        diagnosedNames.insert(reference.name)
        context.diagnose(
            Diagnostic(
                node: Syntax(reference.anchorExpression),
                message: SimpleDiagnostic.provideWithDependencyRequiresSynchronousProvider(
                    memberName: member.name,
                    dependencyName: reference.name,
                    providerThrows: providerThrows
                )
            )
        )
    }

    return diagnosedNames
}

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

internal struct DirectDeferredEagerCallSite {
    let dependencyName: String
    let node: Syntax
}

internal func collectDirectDeferredEagerCalls(
    in closure: ClosureExprSyntax,
    dependencyNames: Set<String>
) -> [DirectDeferredEagerCallSite] {
    guard !dependencyNames.isEmpty else { return [] }

    var callSites: [DirectDeferredEagerCallSite] = []

    func walk(node: Syntax) {
        if node.is(ClosureExprSyntax.self)
            || node.is(FunctionDeclSyntax.self)
            || node.is(InitializerDeclSyntax.self) {
            return
        }

        if let functionCall = node.as(FunctionCallExprSyntax.self),
           let callSite = directDeferredEagerCallSite(in: functionCall, dependencyNames: dependencyNames) {
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

private func directDeferredEagerCallSite(
    in functionCall: FunctionCallExprSyntax,
    dependencyNames: Set<String>
) -> DirectDeferredEagerCallSite? {
    let calledExpression = unwrapDeferredCallExpression(functionCall.calledExpression)

    if let reference = calledExpression.as(DeclReferenceExprSyntax.self),
       dependencyNames.contains(reference.baseName.text) {
        return DirectDeferredEagerCallSite(
            dependencyName: reference.baseName.text,
            node: Syntax(reference)
        )
    }

    if let memberAccess = calledExpression.as(MemberAccessExprSyntax.self),
       let base = unwrapDeferredCallBase(memberAccess.base),
       dependencyNames.contains(base.baseName.text),
       ["callAsFunction", "resolver"].contains(memberAccess.declName.baseName.text) {
        return DirectDeferredEagerCallSite(
            dependencyName: base.baseName.text,
            node: Syntax(memberAccess)
        )
    }

    return nil
}

private func unwrapDeferredCallExpression(_ expression: ExprSyntax) -> ExprSyntax {
    if let tuple = expression.as(TupleExprSyntax.self),
       tuple.elements.count == 1,
       let first = tuple.elements.first,
       first.label == nil {
        return unwrapDeferredCallExpression(first.expression)
    }

    return expression
}

private func unwrapDeferredCallBase(_ expression: ExprSyntax?) -> DeclReferenceExprSyntax? {
    guard let expression else { return nil }

    let unwrapped = unwrapDeferredCallExpression(expression)
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
                "InnoDI defaults to protocol-typed storage so container diffs stay reviewable and the graph stays substitutable. If this dependency must remain a concrete type, opt in explicitly with concrete: true; apply the fixit named '\(SimpleFixIt.addConcreteTrueTitle)' to insert the argument.",
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
    let normalizedMatches = knownNames
        .filter { normalizedDependencyLookupKey($0) == normalizedDependencyLookupKey(dependencyName) }
        .sorted()
    if !normalizedMatches.isEmpty {
        return normalizedMatches
    }
    // Fall back to typo-tolerant matching (Damerau-Levenshtein distance <= 2)
    // when no underscore/case-insensitive variant matches. This catches the
    // common single-character typo case ("apiClent" -> "apiClient") without
    // changing behavior whenever a normalized match is already available.
    let typoMatches = knownNames
        .compactMap { name -> (name: String, distance: Int)? in
            let distance = damerauLevenshteinDistance(dependencyName, name)
            return distance <= 2 ? (name, distance) : nil
        }
        .sorted { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            return lhs.name < rhs.name
        }
    return typoMatches.map(\.name)
}

private func damerauLevenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
    let lhsChars = Array(lhs)
    let rhsChars = Array(rhs)
    let m = lhsChars.count
    let n = rhsChars.count
    if m == 0 { return n }
    if n == 0 { return m }

    var distance = Array(
        repeating: Array(repeating: 0, count: n + 1),
        count: m + 1
    )
    for i in 0...m { distance[i][0] = i }
    for j in 0...n { distance[0][j] = j }

    for i in 1...m {
        for j in 1...n {
            let cost = lhsChars[i - 1] == rhsChars[j - 1] ? 0 : 1
            distance[i][j] = min(
                distance[i - 1][j] + 1,
                distance[i][j - 1] + 1,
                distance[i - 1][j - 1] + cost
            )
            if i > 1, j > 1,
               lhsChars[i - 1] == rhsChars[j - 2],
               lhsChars[i - 2] == rhsChars[j - 1] {
                distance[i][j] = min(distance[i][j], distance[i - 2][j - 2] + 1)
            }
        }
    }
    return distance[m][n]
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
            message: SimpleFixIt(SimpleFixIt.addConcreteTrueTitle, code: .provideConcreteOptInRequired, suffix: "insert-concrete"),
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

internal func makeSubAutoWiringAmbiguousFixIts(
    attribute: AttributeSyntax,
    parentMemberNames: [String]
) -> [FixIt] {
    guard let arguments = attribute.arguments?.as(LabeledExprListSyntax.self),
          !arguments.isEmpty else {
        return []
    }

    var seen = Set<String>()
    let candidates = parentMemberNames.filter { name in
        guard !name.isEmpty else { return false }
        return seen.insert(name).inserted
    }

    let withListBody: String
    if candidates.isEmpty {
        // No parent members at all is unusual (the validator only fires when
        // there are 2+ candidates), but be defensive: still offer the
        // explicit empty-subset spelling that calls `Child()`.
        withListBody = ""
    } else {
        withListBody = candidates.map(renderKeyPathComponent).joined(separator: ", ")
    }

    let insertion = ", with: [\(withListBody)]"
    let position = arguments.endPositionBeforeTrailingTrivia
    return [
        FixIt(
            message: SimpleFixIt(
                "Add explicit with: [...] listing parent members",
                code: .subAutoWiringAmbiguous,
                suffix: "insert-with"
            ),
            changes: [
                .replaceText(
                    range: position..<position,
                    with: insertion,
                    in: Syntax(attribute.root)
                )
            ]
        )
    ]
}

private func renderKeyPathComponent(_ name: String) -> String {
    let unescaped = name.trimmingIdentifierBackticks
    if subContainerFixItSwiftKeywords.contains(unescaped) {
        return "\\.`\(unescaped)`"
    }
    return "\\.\(name)"
}

private extension String {
    var trimmingIdentifierBackticks: String {
        guard first == "`", last == "`", count >= 2 else {
            return self
        }
        return String(dropFirst().dropLast())
    }
}

private let subContainerFixItSwiftKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "open",
    "operator", "private", "precedencegroup", "protocol", "public", "rethrows",
    "static", "struct", "subscript", "typealias", "var", "break", "case",
    "catch", "continue", "default", "defer", "do", "else", "fallthrough",
    "for", "guard", "if", "in", "repeat", "return", "throw", "switch",
    "where", "while", "as", "Any", "catch", "false", "is", "nil",
    "super", "self", "Self", "throw", "throws", "true", "try"
]

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
