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
                  provider: provider.providerEffect
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
        context.emit(
            message,
            at: reference.node
        )
    }

    for reference in member.withDependencyReferences
        where seenNames.insert(reference.name).inserted {
        guard let provider = memberByName[reference.name],
              provider.hasLocallyValidConstructionConfiguration else {
            continue
        }
        let providerThrows: Bool
        switch provider.providerEffect {
        case .synchronous:
            continue
        case .asynchronous:
            providerThrows = false
        case .asynchronousThrowing:
            providerThrows = true
        }

        diagnosedNames.insert(reference.name)
        // `@SubContainerFactory` shares the `Type.self` wiring IR, but its
        // user-facing contract is a child input, not a `with:` provider.
        let message: SimpleDiagnostic = member.assistedFactoryChildType != nil
            ? .subFactoryAsyncParentMember(
                memberName: member.name,
                parentMemberName: reference.name
            )
            : .provideWithDependencyRequiresSynchronousProvider(
                memberName: member.name,
                dependencyName: reference.name,
                providerThrows: providerThrows
            )
        context.emit(message, at: Syntax(reference.anchorExpression))
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
        memberIndex: memberIndex,
        kind: reference?.kind ?? .hard
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
                    unavailableFactoryCandidateMessage(
                        candidates.unavailable,
                        kind: reference?.kind ?? .hard,
                        resolutionContext: resolutionContext,
                        memberIndex: memberIndex
                    ),
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

    let safeRename = candidates.available.count == 1
        && canRenameUnusedFactoryParameter(reference?.token, to: candidates.available[0])
    if candidates.available.count == 1 && !safeRename {
        notes.append(
            Note(
                node: node,
                message: SimpleNote(
                    "Rename parameter '\(dependencyName)' to '\(candidates.available[0])' and update its bound uses manually, checking nested scopes. A parameter-only edit could leave unresolved references or capture another name.",
                    code: .provideUnresolvedFactoryParameter,
                    suffix: "manual-rename"
                )
            )
        )
    }
    let fixIts = safeRename ? makeRenameTokenFixIts(
        token: reference?.token,
        replacementCandidates: candidates.available,
        code: .provideUnresolvedFactoryParameter,
        label: "Rename parameter"
    ) : []

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
                    unavailableHardCandidateMessage(
                        candidates.unavailable,
                        resolutionContext: resolutionContext,
                        memberIndex: memberIndex
                    ),
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
        replacementCandidates: candidates.available.map { "\\Self.\($0)" },
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
    referencedMember: ProvideMemberModel?,
    initializationOrder: ContainerInitializationOrderValue = .declaration
) -> Diagnostic {
    let reason = unavailableDependencyReason(
        member: member,
        referencedMember: referencedMember,
        initializationOrder: initializationOrder
    )
    let guidance: String
    let suffix: String
    switch reason {
    case .transientScope:
        guidance = "Shared members cannot directly inject transient providers. "
            + transientDependencyRecovery(for: referencedMember.map { [$0] } ?? [])
        suffix = "scope"
    case .declarationOrder:
        guidance = "Move shared provider '\(dependencyName)' before '\(member.name)', or opt in to initializationOrder: ContainerInitializationOrder.dependency to order compatible shared providers by dependency."
        suffix = "declaration-order"
    case .incompatibleEffects:
        guidance = incompatibleDependencyEffectsRecovery(memberName: member.name)
        suffix = "effects"
    case .constructionScope:
        guidance = "Use an input or shared provider with compatible effects for '\(dependencyName)', or switch to supported deferred/manual wiring."
        suffix = "scope"
    }
    var notes = [
        Note(
            node: Syntax(member.attribute),
            message: SimpleNote(
                guidance,
                code: .provideUnavailableDependencyReference,
                suffix: suffix
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
                    guidance,
                    code: .provideUnavailableDependencyReference,
                    suffix: "resolution"
                )
            )
        )
    }

    let node = member.closureParameterReferences.first(where: { $0.name == dependencyName })
        .map { Syntax($0.token) }
        ?? member.withDependencyReferences.first(where: { $0.name == dependencyName })
        .map { Syntax($0.anchorExpression) }
        ?? Syntax(member.attribute)
    return Diagnostic(
        node: node,
        message: SimpleDiagnostic.provideUnavailableDependencyReference(
            memberName: member.name,
            dependencyName: dependencyName,
            reason: reason
        ),
        notes: notes
    )
}

private func unavailableDependencyReason(
    member: ProvideMemberModel,
    referencedMember: ProvideMemberModel?,
    initializationOrder: ContainerInitializationOrderValue
) -> DependencyUnavailabilityReason {
    guard let referencedMember else { return .constructionScope }
    if member.scope == .shared && referencedMember.scope == .transient {
        return .transientScope
    }
    if dependencyEffectMismatch(
        consumer: member.constructionEffect,
        provider: referencedMember.providerEffect
    ) != nil {
        return .incompatibleEffects
    }
    if referencedMember.scope == .shared,
       referencedMember.sourceOrder > member.sourceOrder,
       initializationOrder == .declaration {
        return .declarationOrder
    }
    return .constructionScope
}

private func incompatibleDependencyEffectsRecovery(memberName: String) -> String {
    "Use a provider with compatible effects, or rewrite '\(memberName)' with asyncFactory: and the required async/throwing effects. Type.self with: wiring requires synchronous providers; changing declaration order cannot supply missing effects."
}

private func transientDependencyRecovery(for targets: [ProvideMemberModel]) -> String {
    if !targets.isEmpty && targets.allSatisfy({
        $0.hasLocallyValidConstructionConfiguration && $0.supportsLazySoftTarget
    }) {
        return "Use a transient consumer, a deferred Lazy<T> or Provider<T> handle retained for later use with a valid synchronous target, or explicit manual wiring; changing declaration order cannot make it injectable."
    }
    if targets.contains(where: { $0.isAsyncFactory }) {
        return "Use an async transient consumer with compatible throwing effects, or explicit manual wiring; changing declaration order cannot make it injectable. Lazy<T> and Provider<T> cannot wrap asynchronous targets."
    }
    return "Repair the target's construction configuration before choosing a transient consumer or explicit manual wiring; deferred handles require a valid synchronous target, and changing declaration order cannot make it injectable."
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
    memberIndex: Int,
    kind: DependencyKind = .hard
) -> MatchingDependencyCandidates {
    let matches = matchingDependencyCandidates(for: dependencyName, in: resolutionContext.knownNames)
    if kind != .hard {
        // Deferred edges bypass declaration order, but their target contract
        // still applies. Use the same scope/effect rules as exact-name
        // validation rather than recommending a rename that cannot compile.
        let available = matches.filter { name in
            let targets = resolutionContext.members.filter { $0.name == name }
            return !targets.isEmpty && targets.allSatisfy { target in
                target.hasLocallyValidConstructionConfiguration
                    && target.supportsLazySoftTarget
                    && (kind == .soft || target.scope == .transient)
            }
        }
        let availableNames = Set(available)
        return MatchingDependencyCandidates(
            available: available,
            unavailable: matches.filter { !availableNames.contains($0) }
        )
    }
    let available = matches.filter {
        resolutionContext.status(of: $0, forMemberAt: memberIndex) == .available
    }
    let unavailable = matches.filter {
        resolutionContext.status(of: $0, forMemberAt: memberIndex) == .unavailable
    }
    return MatchingDependencyCandidates(available: available, unavailable: unavailable)
}

private func unavailableFactoryCandidateMessage(
    _ names: [String],
    kind: DependencyKind,
    resolutionContext: DependencyResolutionContext,
    memberIndex: Int
) -> String {
    let candidates = names.joined(separator: ", ")
    switch kind {
    case .soft:
        return "Closest matching member cannot be injected as Lazy<T>; Lazy targets must have a valid synchronous construction: \(candidates)."
    case .provider:
        return "Closest matching member cannot be injected as Provider<T>; Provider targets must be valid synchronous .transient providers: \(candidates)."
    case .hard:
        return unavailableHardCandidateMessage(
            names,
            resolutionContext: resolutionContext,
            memberIndex: memberIndex
        )
    }
}

private func unavailableHardCandidateMessage(
    _ names: [String],
    resolutionContext: DependencyResolutionContext,
    memberIndex: Int
) -> String {
    guard resolutionContext.members.indices.contains(memberIndex) else {
        return "Closest matching members are unavailable here: \(names.joined(separator: ", "))."
    }
    let member = resolutionContext.members[memberIndex]
    // Explain each target separately: nearby spellings can have different
    // scopes or effects, so one policy-wide cause would be misleading.
    return names.map { name in
        let targets = resolutionContext.members.filter { $0.name == name }
        let reasons = targets.map {
            unavailableDependencyReason(
                member: member,
                referencedMember: $0,
                initializationOrder: resolutionContext.initializationOrder
            )
        }
        guard let reason = reasons.first, reasons.allSatisfy({ $0 == reason }) else {
            return "Closest matching member '\(name)' is unavailable here; check its declarations and construction requirements."
        }
        switch reason {
        case .transientScope:
            return "Closest matching member '\(name)' has transient scope and cannot be injected directly into a shared member. "
                + transientDependencyRecovery(for: targets)
        case .declarationOrder:
            return "Closest matching member '\(name)' is unavailable in this declaration order. Move the shared provider before '\(member.name)', or opt in to initializationOrder: ContainerInitializationOrder.dependency."
        case .incompatibleEffects:
            return "Closest matching member '\(name)' requires incompatible construction effects. "
                + incompatibleDependencyEffectsRecovery(memberName: member.name)
        case .constructionScope:
            return "Closest matching member '\(name)' is unavailable in this construction scope."
        }
    }.joined(separator: " ")
}

private func normalizedDependencyLookupKey(_ name: String) -> String {
    name
        .filter { $0 != "_" }
        .lowercased()
}

/// A token-only fix is safe only when it cannot break uses of the old
/// binding or capture uses of the new name. This deliberately scans nested
/// scopes too: avoiding a fix-it is safer than pretending to resolve Swift
/// lexical bindings, labels, macro arguments, or shadowed declarations.
private func canRenameUnusedFactoryParameter(_ token: TokenSyntax?, to replacement: String) -> Bool {
    guard let token,
          !isEscapedInnoDIIdentifier(token),
          !swiftReservedKeywords.contains(replacement),
          !replacement.contains("`") else { return false }
    let originalName = unescapedInnoDIIdentifierName(token)
    var ancestor = token.parent
    while let node = ancestor {
        if let closure = node.as(ClosureExprSyntax.self) {
            let conflictingBodyToken = closure.statements.tokens(viewMode: .sourceAccurate).contains {
                let name = unescapedInnoDIIdentifierName($0)
                return name == originalName || name == replacement
            }
            let conflictingSignatureToken = closure.signature?.tokens(viewMode: .sourceAccurate).contains {
                unescapedInnoDIIdentifierName($0) == replacement
            } ?? true
            return !conflictingBodyToken && !conflictingSignatureToken
        }
        ancestor = node.parent
    }
    return false
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
