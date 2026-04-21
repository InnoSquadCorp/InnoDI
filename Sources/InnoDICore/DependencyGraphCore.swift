package struct DependencyGraphNode: Hashable {
    package let id: String
    package let displayName: String
    package let semanticPath: String
    package let isRoot: Bool
    package let validateDAG: Bool
    package let requiredInputs: [String]

    package init(
        id: String,
        displayName: String,
        semanticPath: String,
        isRoot: Bool,
        validateDAG: Bool = true,
        requiredInputs: [String]
    ) {
        self.id = id
        self.displayName = displayName
        self.semanticPath = semanticPath
        self.isRoot = isRoot
        self.validateDAG = validateDAG
        self.requiredInputs = requiredInputs
    }
}

package struct DependencyGraphEdge: Hashable {
    package let fromID: String
    package let toID: String
    package let label: String?
    /// Soft edges are excluded from global DAG cycle detection and rendered
    /// with a dashed style. They originate from factory parameters typed
    /// `Lazy<T>` (see InnoDI's Phase K escape hatch). The current container
    /// collector does not yet populate member-level edges, so this field is
    /// primarily future-proofing — but renderers and `runDAGValidation`
    /// already respect it so downstream collectors can emit soft edges the
    /// moment they have the information.
    package let isSoft: Bool
    /// Provider edges originate from factory parameters typed `Provider<T>`
    /// (Phase L). They are also excluded from cycle detection, but rendered
    /// with a dotted style to distinguish "deferred but repeat-callable"
    /// semantics from `Lazy<T>`'s one-shot deferral. Like `isSoft`, the
    /// container collector does not yet emit member-level provider edges, but
    /// the plumbing is ready end-to-end.
    package let isProvider: Bool
    /// Ownership edges represent a `@SubContainer` relationship — the parent
    /// container owns (either caches for `.shared` or re-builds for
    /// `.transient`) the child container. Ownership edges participate in
    /// cycle detection as hard edges because child construction happens at
    /// parent-init time, but they are rendered with a distinct style and
    /// "owns" label so reviewers can tell container ownership apart from
    /// regular `.input` wiring.
    package let isOwnership: Bool

    package init(
        fromID: String,
        toID: String,
        label: String?,
        isSoft: Bool = false,
        isProvider: Bool = false,
        isOwnership: Bool = false
    ) {
        self.fromID = fromID
        self.toID = toID
        self.label = label
        self.isSoft = isSoft
        self.isProvider = isProvider
        self.isOwnership = isOwnership
    }
}

package func normalizeNodes(_ nodes: [DependencyGraphNode]) -> [DependencyGraphNode] {
    var map: [String: (displayName: String, semanticPath: String, isRoot: Bool, validateDAG: Bool, inputs: Set<String>)] = [:]

    for node in nodes {
        var entry = map[node.id] ?? (
            displayName: node.displayName,
            semanticPath: node.semanticPath,
            isRoot: false,
            validateDAG: true,
            inputs: []
        )
        entry.isRoot = entry.isRoot || node.isRoot
        entry.validateDAG = entry.validateDAG && node.validateDAG
        entry.inputs.formUnion(node.requiredInputs)

        if entry.displayName.isEmpty {
            entry.displayName = node.displayName
        }
        if entry.semanticPath.isEmpty {
            entry.semanticPath = node.semanticPath
        }

        map[node.id] = entry
    }

    return map.keys.sorted().map { id in
        let entry = map[id]!
        return DependencyGraphNode(
            id: id,
            displayName: entry.displayName,
            semanticPath: entry.semanticPath,
            isRoot: entry.isRoot,
            validateDAG: entry.validateDAG,
            requiredInputs: entry.inputs.sorted()
        )
    }
}

/// Builds a DFS adjacency list for global DAG cycle detection.
///
/// Deferred edges are intentionally excluded: `isSoft` (`Lazy<T>` — Phase K)
/// resolves a one-shot value after construction, and `isProvider`
/// (`Provider<T>` — Phase L) resolves a fresh transient on every call. Both
/// kinds participate in rendering but not in cycle detection, matching the
/// per-container validator's hard-only DFS.
///
/// Ownership edges stay hard even if a merged edge still carries deferred
/// flags from upstream callers — parent-owned child construction happens at
/// init time, so ownership must participate in cycle detection.
///
/// The returned adjacency includes every input node as a key (empty list if
/// it has no outgoing hard edges) so callers can reason about isolated nodes
/// uniformly.
package func buildCycleDetectionAdjacency(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) -> [String: [String]] {
    var adjacency: [String: [String]] = [:]
    for node in nodes {
        adjacency[node.id] = []
    }
    for edge in edges where edge.isOwnership || (!edge.isSoft && !edge.isProvider) {
        adjacency[edge.fromID, default: []].append(edge.toID)
    }
    return adjacency
}

package func deduplicateEdges(_ edges: [DependencyGraphEdge]) -> [DependencyGraphEdge] {
    struct EdgeKey: Hashable {
        let fromID: String
        let toID: String
        let label: String?
    }

    func normalizedEdge(
        fromID: String,
        toID: String,
        label: String?,
        isSoft: Bool,
        isProvider: Bool,
        isOwnership: Bool
    ) -> DependencyGraphEdge {
        let effectiveIsOwnership = isOwnership
        let effectiveIsSoft = effectiveIsOwnership ? false : isSoft
        let effectiveIsProvider = effectiveIsOwnership ? false : isProvider
        return DependencyGraphEdge(
            fromID: fromID,
            toID: toID,
            label: label,
            isSoft: effectiveIsSoft,
            isProvider: effectiveIsProvider,
            isOwnership: effectiveIsOwnership
        )
    }

    // Stable: first occurrence wins position. When the same (from, to, label)
    // edge is reported multiple times, the merged edge is `isSoft` only if
    // *every* reporting site said so — any hard occurrence demotes the merge
    // to hard. The same rule applies to `isProvider` and `isOwnership`.
    // When sites disagree about deferred kind (one soft, one provider) we
    // collapse deferred-ness to hard. Ownership also dominates deferred
    // flags: if the merged edge is still ownership, it must be treated as a
    // hard edge for cycle detection.
    var seen: [EdgeKey: Int] = [:]
    var result: [DependencyGraphEdge] = []

    for edge in edges {
        let key = EdgeKey(fromID: edge.fromID, toID: edge.toID, label: edge.label)
        if let existingIndex = seen[key] {
            let existing = result[existingIndex]
            let mergedIsSoft = existing.isSoft && edge.isSoft
            let mergedIsProvider = existing.isProvider && edge.isProvider
            let mergedIsOwnership = existing.isOwnership && edge.isOwnership
            // If one occurrence is soft and another is provider, they are
            // different deferred wrappers at different sites — demote to hard.
            let deferredMismatch = (existing.isSoft && edge.isProvider)
                || (existing.isProvider && edge.isSoft)
            if existing.isSoft != mergedIsSoft
                || existing.isProvider != mergedIsProvider
                || existing.isOwnership != mergedIsOwnership
                || deferredMismatch {
                result[existingIndex] = normalizedEdge(
                    fromID: edge.fromID,
                    toID: edge.toID,
                    label: edge.label,
                    isSoft: deferredMismatch ? false : mergedIsSoft,
                    isProvider: deferredMismatch ? false : mergedIsProvider,
                    isOwnership: mergedIsOwnership
                )
            }
        } else {
            seen[key] = result.count
            result.append(
                normalizedEdge(
                    fromID: edge.fromID,
                    toID: edge.toID,
                    label: edge.label,
                    isSoft: edge.isSoft,
                    isProvider: edge.isProvider,
                    isOwnership: edge.isOwnership
                )
            )
        }
    }

    return result
}
