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

    package init(fromID: String, toID: String, label: String?, isSoft: Bool = false) {
        self.fromID = fromID
        self.toID = toID
        self.label = label
        self.isSoft = isSoft
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
/// Soft edges (`DependencyGraphEdge.isSoft == true`) are intentionally
/// excluded — they originate from `Lazy<T>` factory parameters whose
/// resolution is deferred until after container construction, so any cycle
/// they participate in is not traversed at init time. The filter matches the
/// per-container validator in `DIContainerValidator` (hard-only DFS).
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
    for edge in edges where !edge.isSoft {
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

    // Stable: first occurrence wins position. When the same (from, to, label)
    // edge is reported multiple times, the merged edge is `isSoft` only if
    // *every* reporting site said so — any hard occurrence demotes the merge
    // to hard. This matches the validator's hard-wins rule: a cycle that is
    // broken on one path but hard on another is still a cycle.
    var seen: [EdgeKey: Int] = [:]
    var result: [DependencyGraphEdge] = []

    for edge in edges {
        let key = EdgeKey(fromID: edge.fromID, toID: edge.toID, label: edge.label)
        if let existingIndex = seen[key] {
            if result[existingIndex].isSoft && !edge.isSoft {
                result[existingIndex] = DependencyGraphEdge(
                    fromID: edge.fromID,
                    toID: edge.toID,
                    label: edge.label,
                    isSoft: false
                )
            }
        } else {
            seen[key] = result.count
            result.append(edge)
        }
    }

    return result
}
