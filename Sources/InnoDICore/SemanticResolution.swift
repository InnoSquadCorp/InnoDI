import SwiftSyntax

package struct SemanticTypeReference: Codable, Equatable, Sendable {
    package let displayPath: String
    package let components: [String]

    package init(displayPath: String, components: [String]) {
        self.displayPath = displayPath
        self.components = components
    }
}

package struct SemanticNominalTypeRecord: Codable, Equatable, Sendable {
    package let path: String
    package let components: [String]

    package init(path: String, components: [String]) {
        self.path = path
        self.components = components
    }
}

package struct SemanticTypeAliasRecord: Codable, Equatable, Sendable {
    package let path: String
    package let components: [String]
    package let target: SemanticTypeReference

    package init(path: String, components: [String], target: SemanticTypeReference) {
        self.path = path
        self.components = components
        self.target = target
    }
}

package enum SemanticResolutionState: String, Codable, Equatable, Sendable {
    case resolved
    case ambiguous
    case excluded
    case unresolved
}

package struct SemanticResolutionResult: Codable, Equatable, Sendable {
    package let state: SemanticResolutionState
    package let resolvedPath: String?
    package let candidates: [String]
    package let excludedReason: String?
    package let aliasExpansionTrace: [String]
    package let usedSuffixFallback: Bool

    package init(
        state: SemanticResolutionState,
        resolvedPath: String? = nil,
        candidates: [String] = [],
        excludedReason: String? = nil,
        aliasExpansionTrace: [String] = [],
        usedSuffixFallback: Bool = false
    ) {
        self.state = state
        self.resolvedPath = resolvedPath
        self.candidates = candidates
        self.excludedReason = excludedReason
        self.aliasExpansionTrace = aliasExpansionTrace
        self.usedSuffixFallback = usedSuffixFallback
    }
}

package struct SemanticResolverIndex: Equatable, Sendable {
    package let nominalTypes: [SemanticNominalTypeRecord]
    package let typeAliases: [SemanticTypeAliasRecord]

    package init(
        nominalTypes: [SemanticNominalTypeRecord],
        topLevelTypeAliases: [SemanticTypeAliasRecord]
    ) {
        self.nominalTypes = nominalTypes
        self.typeAliases = topLevelTypeAliases
    }

    package func resolvePath(
        for reference: SemanticTypeReference,
        candidatePaths: Set<String>
    ) -> SemanticResolutionResult {
        let expansions = expandedReferences(for: reference)
        let exactMatches = uniqueMatches(
            for: expansions.compactMap { candidate in
                candidatePaths.contains(candidate.reference.displayPath)
                    ? ResolutionMatch(
                        path: candidate.reference.displayPath,
                        aliasExpansionTrace: candidate.aliasExpansionTrace,
                        usedSuffixFallback: false
                    )
                    : nil
            }
        )
        if let result = resolutionResult(for: exactMatches) {
            return result
        }

        let suffixResolutionMatches = uniqueMatches(
            for: expansions.flatMap { candidate in
                suffixMatches(for: candidate.reference.components, candidatePaths: candidatePaths).map { path in
                    ResolutionMatch(
                        path: path,
                        aliasExpansionTrace: candidate.aliasExpansionTrace,
                        usedSuffixFallback: true
                    )
                }
            }
        )
        if let result = resolutionResult(for: suffixResolutionMatches) {
            return result
        }

        return SemanticResolutionResult(state: .unresolved, aliasExpansionTrace: expansions.flatMap(\.aliasExpansionTrace))
    }

    private func suffixMatches(
        for components: [String],
        candidatePaths: Set<String>
    ) -> [String] {
        guard !components.isEmpty else {
            return []
        }

        return candidatePaths
            .filter { path in
                let candidateComponents = path.split(separator: ".").map(String.init)
                if candidateComponents.count >= components.count {
                    return Array(candidateComponents.suffix(components.count)) == components
                }

                return Array(components.suffix(candidateComponents.count)) == candidateComponents
            }
            .sorted()
    }

    private func expandedReferences(for reference: SemanticTypeReference) -> [ResolutionCandidate] {
        var queue: [ResolutionCandidate] = [
            ResolutionCandidate(reference: reference, aliasExpansionTrace: [])
        ]
        var visited: Set<String> = [reference.displayPath]
        var results: [ResolutionCandidate] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            results.append(current)

            for expansion in directAliasExpansions(for: current.reference) {
                let key = expansion.reference.displayPath
                if visited.insert(key).inserted {
                    queue.append(
                        ResolutionCandidate(
                            reference: expansion.reference,
                            aliasExpansionTrace: current.aliasExpansionTrace + expansion.aliasExpansionTrace
                        )
                    )
                }
            }
        }

        return results
    }

    private func directAliasExpansions(for reference: SemanticTypeReference) -> [ResolutionCandidate] {
        guard !reference.components.isEmpty else {
            return []
        }

        var expansions: [ResolutionCandidate] = []

        for prefixLength in stride(from: reference.components.count, through: 1, by: -1) {
            let prefix = Array(reference.components.prefix(prefixLength))
            let remainder = Array(reference.components.dropFirst(prefixLength))
            let matches = matchingAliases(for: prefix)

            for match in matches {
                let components = match.target.components + remainder
                expansions.append(
                    ResolutionCandidate(
                        reference: SemanticTypeReference(
                            displayPath: components.joined(separator: "."),
                            components: components
                        ),
                        aliasExpansionTrace: [match.path]
                    )
                )
            }
        }

        return expansions
    }

    private func matchingAliases(for referencePrefix: [String]) -> [SemanticTypeAliasRecord] {
        typeAliases
            .filter { alias in
                if alias.components == referencePrefix {
                    return true
                }
                guard alias.components.count >= referencePrefix.count else {
                    return false
                }
                return Array(alias.components.suffix(referencePrefix.count)) == referencePrefix
            }
            .sorted { $0.path < $1.path }
    }

    private func uniqueMatches(for matches: [ResolutionMatch]) -> [ResolutionMatch] {
        var seen: Set<String> = []
        var unique: [ResolutionMatch] = []
        for match in matches.sorted(by: { lhs, rhs in
            if lhs.path != rhs.path {
                return lhs.path < rhs.path
            }
            if lhs.usedSuffixFallback != rhs.usedSuffixFallback {
                return lhs.usedSuffixFallback == false
            }
            return lhs.aliasExpansionTrace.joined(separator: "->") < rhs.aliasExpansionTrace.joined(separator: "->")
        }) {
            if seen.insert(match.path).inserted {
                unique.append(match)
            }
        }
        return unique
    }

    private func resolutionResult(for matches: [ResolutionMatch]) -> SemanticResolutionResult? {
        guard !matches.isEmpty else {
            return nil
        }
        if matches.count == 1, let match = matches.first {
            return SemanticResolutionResult(
                state: .resolved,
                resolvedPath: match.path,
                aliasExpansionTrace: match.aliasExpansionTrace,
                usedSuffixFallback: match.usedSuffixFallback
            )
        }
        return SemanticResolutionResult(
            state: .ambiguous,
            candidates: matches.map(\.path),
            aliasExpansionTrace: Array(Set(matches.flatMap(\.aliasExpansionTrace))).sorted(),
            usedSuffixFallback: matches.contains(where: \.usedSuffixFallback)
        )
    }
}

private struct ResolutionCandidate {
    let reference: SemanticTypeReference
    let aliasExpansionTrace: [String]
}

private struct ResolutionMatch {
    let path: String
    let aliasExpansionTrace: [String]
    let usedSuffixFallback: Bool
}

package func normalizedSemanticTypeReference(_ type: TypeSyntax) -> SemanticTypeReference? {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        guard identifier.genericArgumentClause == nil else {
            return nil
        }

        let component = identifier.name.text
        return SemanticTypeReference(displayPath: component, components: [component])
    }

    if let member = type.as(MemberTypeSyntax.self) {
        guard member.genericArgumentClause == nil,
              let base = normalizedSemanticTypeReference(member.baseType) else {
            return nil
        }

        let components = base.components + [member.name.text]
        return SemanticTypeReference(
            displayPath: components.joined(separator: "."),
            components: components
        )
    }

    if let attributed = type.as(AttributedTypeSyntax.self) {
        return normalizedSemanticTypeReference(attributed.baseType)
    }

    return nil
}

package func normalizedSemanticExpressionReference(_ expr: ExprSyntax) -> SemanticTypeReference? {
    if let declReference = expr.as(DeclReferenceExprSyntax.self) {
        let component = declReference.baseName.text
        return SemanticTypeReference(displayPath: component, components: [component])
    }

    if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
        let memberName = memberAccess.declName.baseName.text
        if memberName == "init" || memberName == "self", let base = memberAccess.base {
            return normalizedSemanticExpressionReference(base)
        }

        if let base = memberAccess.base,
           let baseReference = normalizedSemanticExpressionReference(base) {
            let components = baseReference.components + [memberName]
            return SemanticTypeReference(
                displayPath: components.joined(separator: "."),
                components: components
            )
        }

        return SemanticTypeReference(displayPath: memberName, components: [memberName])
    }

    if let genericSpecialization = expr.as(GenericSpecializationExprSyntax.self) {
        return normalizedSemanticExpressionReference(genericSpecialization.expression)
    }

    if let functionCall = expr.as(FunctionCallExprSyntax.self) {
        return normalizedSemanticExpressionReference(functionCall.calledExpression)
    }

    if let forceUnwrap = expr.as(ForceUnwrapExprSyntax.self) {
        return normalizedSemanticExpressionReference(forceUnwrap.expression)
    }

    if let optionalChaining = expr.as(OptionalChainingExprSyntax.self) {
        return normalizedSemanticExpressionReference(optionalChaining.expression)
    }

    if let tryExpr = expr.as(TryExprSyntax.self) {
        return normalizedSemanticExpressionReference(tryExpr.expression)
    }

    if let awaitExpr = expr.as(AwaitExprSyntax.self) {
        return normalizedSemanticExpressionReference(awaitExpr.expression)
    }

    return nil
}
