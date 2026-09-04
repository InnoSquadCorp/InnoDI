import Foundation
import InnoDICore
import InnoDIDependencyGraphCore

enum GraphInspectionError: Error, Equatable, LocalizedError {
    case nodeNotFound(selector: String)
    case ambiguousNode(selector: String, candidates: [String])
    case noRoots
    case unreachableFromRoots(selector: String)
    case unsupportedSchema(path: String, found: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .nodeNotFound(let selector):
            return "No container matches '\(selector)'. Use an exact graph ID, semantic path, or display name."
        case .ambiguousNode(let selector, let candidates):
            return "Container selector '\(selector)' is ambiguous. Candidates: \(candidates.joined(separator: ", "))"
        case .noRoots:
            return "This query requires at least one explicit graph root."
        case .unreachableFromRoots(let selector):
            return "Container '\(selector)' is not reachable from any explicit graph root."
        case .unsupportedSchema(let path, let found, let expected):
            return "Graph document '\(path)' uses schema v\(found); --diff currently requires schema v\(expected)."
        }
    }
}

func renderGraphQuery(
    _ query: GraphQuery,
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) throws -> String {
    switch query {
    case .why(let selector):
        return try renderWhyQuery(selector: selector, nodes: nodes, edges: edges)
    case .dependents(let selector):
        return try renderDependentsQuery(selector: selector, nodes: nodes, edges: edges)
    case .unused:
        return try renderUnusedQuery(nodes: nodes, edges: edges)
    }
}

func loadGraphJSONDocument(at path: String) throws -> GraphJSON.Document {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let document = try JSONDecoder().decode(GraphJSON.Document.self, from: data)
    guard document.schemaVersion == GraphJSON.currentSchemaVersion else {
        throw GraphInspectionError.unsupportedSchema(
            path: path,
            found: document.schemaVersion,
            expected: GraphJSON.currentSchemaVersion
        )
    }
    return document
}

func renderGraphDiff(
    before: GraphJSON.Document,
    after: GraphJSON.Document
) -> String {
    renderGraphDiff(compareGraphDocuments(before: before, after: after))
}

struct GraphDiffReport: Equatable {
    let beforeScope: GraphJSON.Scope
    let afterScope: GraphJSON.Scope
    let addedNodeIDs: [String]
    let removedNodeIDs: [String]
    let changedNodes: [String]
    let addedEdgeIDs: [String]
    let removedEdgeIDs: [String]

    var hasChanges: Bool {
        beforeScope != afterScope
            || !addedNodeIDs.isEmpty
            || !removedNodeIDs.isEmpty
            || !changedNodes.isEmpty
            || !addedEdgeIDs.isEmpty
            || !removedEdgeIDs.isEmpty
    }
}

func compareGraphDocuments(
    before: GraphJSON.Document,
    after: GraphJSON.Document
) -> GraphDiffReport {
    let beforeNodes = before.nodes.reduce(into: [String: GraphJSON.Node]()) {
        $0[$1.id] = $0[$1.id] ?? $1
    }
    let afterNodes = after.nodes.reduce(into: [String: GraphJSON.Node]()) {
        $0[$1.id] = $0[$1.id] ?? $1
    }
    let beforeIDs = Set(beforeNodes.keys)
    let afterIDs = Set(afterNodes.keys)

    let addedNodeIDs = afterIDs.subtracting(beforeIDs).sorted()
    let removedNodeIDs = beforeIDs.subtracting(afterIDs).sorted()
    let changedNodes = beforeIDs.intersection(afterIDs)
        .filter { beforeNodes[$0] != afterNodes[$0] }
        .sorted()
        .map { id in
            guard let old = beforeNodes[id], let new = afterNodes[id] else { return id }
            return "\(id): \(nodeChangeDescription(before: old, after: new))"
        }

    let beforeEdgeIDs = Set(before.edges.map(graphJSONEdgeIdentity))
    let afterEdgeIDs = Set(after.edges.map(graphJSONEdgeIdentity))

    return GraphDiffReport(
        beforeScope: before.scope,
        afterScope: after.scope,
        addedNodeIDs: addedNodeIDs,
        removedNodeIDs: removedNodeIDs,
        changedNodes: changedNodes,
        addedEdgeIDs: afterEdgeIDs.subtracting(beforeEdgeIDs).sorted(),
        removedEdgeIDs: beforeEdgeIDs.subtracting(afterEdgeIDs).sorted()
    )
}

func renderGraphDiff(_ report: GraphDiffReport) -> String {
    var lines = ["InnoDI Graph Diff (schema v\(GraphJSON.currentSchemaVersion))"]
    if report.beforeScope == report.afterScope {
        lines.append("Scope: unchanged")
    } else {
        lines.append(
            "Scope: \(scopeDescription(report.beforeScope)) -> \(scopeDescription(report.afterScope))"
        )
    }

    appendDiffSection(
        title: "Nodes added",
        marker: "+",
        values: report.addedNodeIDs,
        to: &lines
    )
    appendDiffSection(
        title: "Nodes removed",
        marker: "-",
        values: report.removedNodeIDs,
        to: &lines
    )
    appendDiffSection(
        title: "Nodes changed",
        marker: "~",
        values: report.changedNodes,
        to: &lines
    )
    appendDiffSection(
        title: "Edges added",
        marker: "+",
        values: report.addedEdgeIDs,
        to: &lines
    )
    appendDiffSection(
        title: "Edges removed",
        marker: "-",
        values: report.removedEdgeIDs,
        to: &lines
    )

    return lines.joined(separator: "\n") + "\n"
}

private func renderWhyQuery(
    selector: String,
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) throws -> String {
    let target = try resolveGraphNode(selector: selector, nodes: nodes)
    let roots = nodes.filter(\.isRoot).sorted { $0.id < $1.id }
    guard !roots.isEmpty else { throw GraphInspectionError.noRoots }

    if target.isRoot {
        return "Why \(queryLabel(for: target, nodes: nodes))\n- \(queryLabel(for: target, nodes: nodes)) [ROOT]\n"
    }

    let edgesBySource = Dictionary(grouping: edges, by: \.fromID)
        .mapValues { $0.sorted(by: graphEdgeCanonicalOrder) }
    var queue = roots.map(\.id)
    var nextIndex = 0
    var visited = Set(queue)
    var predecessor: [String: (nodeID: String, edge: DependencyGraphEdge)] = [:]

    while nextIndex < queue.count, !visited.contains(target.id) {
        let sourceID = queue[nextIndex]
        nextIndex += 1
        for edge in edgesBySource[sourceID] ?? [] where visited.insert(edge.toID).inserted {
            predecessor[edge.toID] = (sourceID, edge)
            queue.append(edge.toID)
        }
    }

    guard visited.contains(target.id) else {
        throw GraphInspectionError.unreachableFromRoots(selector: selector)
    }

    let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    var path: [DependencyGraphEdge] = []
    var cursor = target.id
    while let previous = predecessor[cursor] {
        path.append(previous.edge)
        cursor = previous.nodeID
    }
    path.reverse()

    var lines = ["Why \(queryLabel(for: target, nodes: nodes))"]
    for edge in path {
        let from = nodesByID[edge.fromID].map { queryLabel(for: $0, nodes: nodes) }
            ?? edge.fromID
        let to = nodesByID[edge.toID].map { queryLabel(for: $0, nodes: nodes) }
            ?? edge.toID
        lines.append("- \(from) --[\(edgeDescription(edge))]--> \(to)")
    }
    return lines.joined(separator: "\n") + "\n"
}

private func renderDependentsQuery(
    selector: String,
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) throws -> String {
    let target = try resolveGraphNode(selector: selector, nodes: nodes)
    let incomingByDestination = Dictionary(grouping: edges, by: \.toID)
        .mapValues { $0.sorted(by: graphEdgeCanonicalOrder) }
    var queue = [target.id]
    var nextIndex = 0
    var distances = [target.id: 0]

    while nextIndex < queue.count {
        let destinationID = queue[nextIndex]
        nextIndex += 1
        let nextDistance = (distances[destinationID] ?? 0) + 1
        for edge in incomingByDestination[destinationID] ?? []
            where distances[edge.fromID] == nil {
            distances[edge.fromID] = nextDistance
            queue.append(edge.fromID)
        }
    }

    let dependents = nodes.filter { $0.id != target.id && distances[$0.id] != nil }
        .sorted {
            let lhsDistance = distances[$0.id] ?? .max
            let rhsDistance = distances[$1.id] ?? .max
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return $0.id < $1.id
        }

    var lines = ["Dependents of \(queryLabel(for: target, nodes: nodes)) (\(dependents.count))"]
    for node in dependents {
        lines.append(
            "- \(queryLabel(for: node, nodes: nodes)) (distance \(distances[node.id] ?? 0))"
        )
    }
    return lines.joined(separator: "\n") + "\n"
}

private func renderUnusedQuery(
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge]
) throws -> String {
    let roots = nodes.filter(\.isRoot).sorted { $0.id < $1.id }
    guard !roots.isEmpty else { throw GraphInspectionError.noRoots }

    let edgesBySource = Dictionary(grouping: edges, by: \.fromID)
    var queue = roots.map(\.id)
    var nextIndex = 0
    var reachable = Set(queue)
    while nextIndex < queue.count {
        let sourceID = queue[nextIndex]
        nextIndex += 1
        for edge in edgesBySource[sourceID] ?? [] where reachable.insert(edge.toID).inserted {
            queue.append(edge.toID)
        }
    }

    let unused = nodes.filter { !reachable.contains($0.id) }.sorted { $0.id < $1.id }
    var lines = ["Unused containers (\(unused.count))"]
    lines.append(contentsOf: unused.map { "- \(queryLabel(for: $0, nodes: nodes))" })
    return lines.joined(separator: "\n") + "\n"
}

private func resolveGraphNode(
    selector: String,
    nodes: [DependencyGraphNode]
) throws -> DependencyGraphNode {
    for keyPath in [\DependencyGraphNode.id, \.semanticPath, \.displayName] {
        let matches = nodes.filter { $0[keyPath: keyPath] == selector }
        if matches.count == 1 {
            return matches[0]
        }
        if matches.count > 1 {
            throw GraphInspectionError.ambiguousNode(
                selector: selector,
                candidates: matches.map(\.id).sorted()
            )
        }
    }
    throw GraphInspectionError.nodeNotFound(selector: selector)
}

private func queryLabel(
    for node: DependencyGraphNode,
    nodes: [DependencyGraphNode]
) -> String {
    let duplicateDisplayName = nodes.lazy.filter { $0.displayName == node.displayName }.count > 1
    return duplicateDisplayName ? node.semanticPath : node.displayName
}

private func graphEdgeCanonicalOrder(
    _ lhs: DependencyGraphEdge,
    _ rhs: DependencyGraphEdge
) -> Bool {
    if lhs.fromID != rhs.fromID { return lhs.fromID < rhs.fromID }
    if lhs.toID != rhs.toID { return lhs.toID < rhs.toID }
    if edgeDescription(lhs) != edgeDescription(rhs) {
        return edgeDescription(lhs) < edgeDescription(rhs)
    }
    return (lhs.label ?? "") < (rhs.label ?? "")
}

private func edgeDescription(_ edge: DependencyGraphEdge) -> String {
    let kind: String
    if edge.isContribution {
        let index = edge.order.map(String.init) ?? "?"
        let contributor = edge.contributor ?? "?"
        kind = "contributes[\(index)]: \(contributor)"
    } else if edge.isAssistedFactoryOwnership {
        kind = "factory owns"
    } else if edge.isOwnership {
        kind = "owns"
    } else if edge.isProvider {
        kind = "provider"
    } else if edge.isSoft {
        kind = "lazy"
    } else {
        kind = "depends"
    }
    return edge.label.map { "\(kind): \($0)" } ?? kind
}

private func graphJSONEdgeIdentity(_ edge: GraphJSON.Edge) -> String {
    let label = edge.label.map { ": \($0)" } ?? ""
    let contributor = edge.contributor.map { ", contributor=\($0)" } ?? ""
    let order = edge.order.map { ", order=\($0)" } ?? ""
    return "\(edge.from) --[\(edge.kind.rawValue)\(label)\(contributor)\(order)]--> \(edge.to)"
}

private func scopeDescription(_ scope: GraphJSON.Scope) -> String {
    "\(scope.primaryTargetID), pruning=\(scope.rootPruning.rawValue)"
}

private func nodeChangeDescription(
    before: GraphJSON.Node,
    after: GraphJSON.Node
) -> String {
    var changes: [String] = []
    if before.displayName != after.displayName {
        changes.append("displayName \(before.displayName) -> \(after.displayName)")
    }
    if before.semanticPath != after.semanticPath {
        changes.append("semanticPath \(before.semanticPath) -> \(after.semanticPath)")
    }
    if before.isRoot != after.isRoot {
        changes.append("root \(before.isRoot) -> \(after.isRoot)")
    }
    if before.requiredInputs != after.requiredInputs {
        changes.append(
            "inputs [\(before.requiredInputs.joined(separator: ", "))] -> [\(after.requiredInputs.joined(separator: ", "))]"
        )
    }
    if before.assistedInputs != after.assistedInputs {
        changes.append(
            "assisted [\(before.assistedInputs.joined(separator: ", "))] -> [\(after.assistedInputs.joined(separator: ", "))]"
        )
    }
    return changes.joined(separator: "; ")
}

private func appendDiffSection(
    title: String,
    marker: String,
    values: [String],
    to lines: inout [String]
) {
    lines.append("\(title) (\(values.count))")
    lines.append(contentsOf: values.map { "\(marker) \($0)" })
}
