import Foundation

package struct DependencyGraphNode: Hashable {
    package let id: String
    package let displayName: String
    package let isRoot: Bool
    package let requiredInputs: [String]

    package init(id: String, displayName: String, isRoot: Bool, requiredInputs: [String]) {
        self.id = id
        self.displayName = displayName
        self.isRoot = isRoot
        self.requiredInputs = requiredInputs
    }
}

package struct DependencyGraphEdge: Hashable {
    package let fromID: String
    package let toID: String
    package let label: String?

    package init(fromID: String, toID: String, label: String?) {
        self.fromID = fromID
        self.toID = toID
        self.label = label
    }
}

package func normalizeNodes(_ nodes: [DependencyGraphNode]) -> [DependencyGraphNode] {
    var map: [String: (displayName: String, isRoot: Bool, inputs: Set<String>)] = [:]

    for node in nodes {
        var entry = map[node.id] ?? (displayName: node.displayName, isRoot: false, inputs: [])
        entry.isRoot = entry.isRoot || node.isRoot
        entry.inputs.formUnion(node.requiredInputs)

        if entry.displayName.isEmpty {
            entry.displayName = node.displayName
        }

        map[node.id] = entry
    }

    return map.keys.sorted().map { id in
        let entry = map[id]!
        return DependencyGraphNode(
            id: id,
            displayName: entry.displayName,
            isRoot: entry.isRoot,
            requiredInputs: entry.inputs.sorted()
        )
    }
}

package func deduplicateEdges(_ edges: [DependencyGraphEdge]) -> [DependencyGraphEdge] {
    var seen: Set<String> = []
    var result: [DependencyGraphEdge] = []

    for edge in edges {
        let key = "\(edge.fromID)->\(edge.toID)|\(edge.label ?? "")"
        if seen.insert(key).inserted {
            result.append(edge)
        }
    }

    return result
}
