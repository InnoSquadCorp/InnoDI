import Foundation
import InnoDICore
import InnoDIDependencyGraphCore

enum GraphInspectionError: Error, Equatable, LocalizedError {
    case nodeNotFound(selector: String)
    case ambiguousNode(selector: String, candidates: [String])
    case noRoots
    case unreachableFromRoots(selector: String)
    case unsupportedSchema(path: String, found: Int, expected: Int)
    case invalidDocument(path: String, reason: String)
    case providerNotFound(selector: String)
    case ambiguousProvider(selector: String, candidates: [String])

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
        case .invalidDocument(let path, let reason):
            return "Graph document '\(path)' is invalid: \(reason)"
        case .providerNotFound(let selector):
            return "No provider matches '\(selector)'. Use container.member or an exact provider ID."
        case .ambiguousProvider(let selector, let candidates):
            return "Provider selector '\(selector)' is ambiguous. Candidates: \(candidates.joined(separator: ", "))"
        }
    }
}

func renderGraphQuery(
    _ query: GraphQuery,
    nodes: [DependencyGraphNode],
    edges: [DependencyGraphEdge],
    providers: [DependencyGraphProvider] = []
) throws -> String {
    switch query {
    case .why(let selector):
        if looksLikeProviderSelector(selector, providers: providers) {
            return try renderProviderWhy(selector: selector, nodes: nodes, providers: providers)
        }
        return try renderWhyQuery(selector: selector, nodes: nodes, edges: edges)
    case .dependents(let selector):
        if looksLikeProviderSelector(selector, providers: providers) {
            return try renderProviderDependents(selector: selector, nodes: nodes, providers: providers)
        }
        return try renderDependentsQuery(selector: selector, nodes: nodes, edges: edges)
    case .unused:
        return try renderUnusedQuery(nodes: nodes, edges: edges)
    }
}

private func looksLikeProviderSelector(
    _ selector: String,
    providers: [DependencyGraphProvider]
) -> Bool {
    providers.contains { provider in
        provider.id == selector || provider.name == selector
            || provider.id.hasSuffix(".\(selector)")
            || selector.hasSuffix(".\(provider.name)")
    }
}

private func resolveProvider(
    selector: String,
    nodes: [DependencyGraphNode],
    providers: [DependencyGraphProvider]
) throws -> DependencyGraphProvider {
    let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    let matches = providers.filter { provider in
        guard let node = nodesByID[provider.containerID] else { return false }
        return provider.id == selector
            || "\(node.semanticPath).\(provider.name)" == selector
            || "\(node.displayName).\(provider.name)" == selector
            || provider.name == selector
    }
    if matches.count == 1 { return matches[0] }
    if matches.count > 1 {
        throw GraphInspectionError.ambiguousProvider(
            selector: selector,
            candidates: matches.map(\.id).sorted()
        )
    }
    throw GraphInspectionError.providerNotFound(selector: selector)
}

private func renderProviderWhy(
    selector: String,
    nodes: [DependencyGraphNode],
    providers: [DependencyGraphProvider]
) throws -> String {
    let provider = try resolveProvider(selector: selector, nodes: nodes, providers: providers)
    let dependencies = provider.dependencies.map { "\(provider.containerID).\($0)" }
    var lines = [
        "Why provider \(provider.id)",
        "- Source: \(provider.source.path):\(provider.source.line):\(provider.source.column)",
        "- Contract: role=\(provider.role.rawValue), type=\(provider.type), lifetime=\(provider.lifetime.rawValue), initialization=\(provider.initialization.rawValue), isolation=\(provider.isolation.rawValue), effect=\(provider.effect.rawValue)",
    ]
    if dependencies.isEmpty {
        lines.append("- Dependencies: none")
    } else {
        lines.append("- Dependencies: \(dependencies.joined(separator: ", "))")
    }
    lines.append("- Runtime provenance: attach a DITraceContext to observe override, cache, and async events")
    return lines.joined(separator: "\n") + "\n"
}

private func renderProviderDependents(
    selector: String,
    nodes: [DependencyGraphNode],
    providers: [DependencyGraphProvider]
) throws -> String {
    let target = try resolveProvider(selector: selector, nodes: nodes, providers: providers)
    let providersByID = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
    var distances = [target.id: 0]
    var queue = [target.id]
    var cursor = 0
    while cursor < queue.count {
        let dependencyID = queue[cursor]
        cursor += 1
        let nextDistance = (distances[dependencyID] ?? 0) + 1
        for candidate in providers where distances[candidate.id] == nil {
            let candidateDependencies = candidate.dependencies.map {
                "\(candidate.containerID).\($0)"
            }
            if candidateDependencies.contains(dependencyID) {
                distances[candidate.id] = nextDistance
                queue.append(candidate.id)
            }
        }
    }
    let dependents = distances.keys.compactMap { providersByID[$0] }
        .filter { $0.id != target.id }
        .sorted {
            let lhs = distances[$0.id] ?? .max
            let rhs = distances[$1.id] ?? .max
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    var lines = ["Dependents of provider \(target.id) (\(dependents.count))"]
    lines.append(contentsOf: dependents.map {
        "- \($0.id) (distance \(distances[$0.id] ?? 0), source \($0.source.path):\($0.source.line):\($0.source.column))"
    })
    return lines.joined(separator: "\n") + "\n"
}

func loadGraphJSONDocument(at path: String) throws -> GraphJSON.Document {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    struct SchemaHeader: Decodable { let schemaVersion: Int }
    let decoder = JSONDecoder()
    let header = try decoder.decode(SchemaHeader.self, from: data)
    guard header.schemaVersion == GraphJSON.currentSchemaVersion else {
        throw GraphInspectionError.unsupportedSchema(
            path: path,
            found: header.schemaVersion,
            expected: GraphJSON.currentSchemaVersion
        )
    }
    let document = try decoder.decode(GraphJSON.Document.self, from: data)
    try validateGraphJSONDocument(document, path: path)
    return document
}

private func validateGraphJSONDocument(
    _ document: GraphJSON.Document,
    path: String
) throws {
    let nodeIDs = document.nodes.map(\.id)
    if let duplicate = firstDuplicate(in: nodeIDs) {
        throw GraphInspectionError.invalidDocument(
            path: path,
            reason: "duplicate node ID '\(duplicate)'"
        )
    }
    let validNodeIDs = Set(nodeIDs)
    for edge in document.edges {
        guard validNodeIDs.contains(edge.from) else {
            throw GraphInspectionError.invalidDocument(
                path: path,
                reason: "edge source '\(edge.from)' does not name a node"
            )
        }
        guard validNodeIDs.contains(edge.to) else {
            throw GraphInspectionError.invalidDocument(
                path: path,
                reason: "edge destination '\(edge.to)' does not name a node"
            )
        }
    }
    if let duplicate = firstDuplicate(in: document.providers.map(\.id)) {
        throw GraphInspectionError.invalidDocument(
            path: path,
            reason: "duplicate provider ID '\(duplicate)'"
        )
    }
    let providersByID = Dictionary(
        uniqueKeysWithValues: document.providers.map { ($0.id, $0) }
    )
    for provider in document.providers {
        guard validNodeIDs.contains(provider.containerID) else {
            throw GraphInspectionError.invalidDocument(
                path: path,
                reason: "provider '\(provider.id)' names missing container '\(provider.containerID)'"
            )
        }
        guard provider.source.line > 0, provider.source.column > 0 else {
            throw GraphInspectionError.invalidDocument(
                path: path,
                reason: "provider '\(provider.id)' has an invalid source location"
            )
        }
        if let collection = provider.collection {
            let expectsKeys = collection.kind == .keyed
                || collection.kind == .keyedProviders
            let keys = collection.entries.compactMap(\.key)
            if expectsKeys, keys.count != collection.entries.count {
                throw GraphInspectionError.invalidDocument(
                    path: path,
                    reason: "provider '\(provider.id)' keyed collection has an entry without a key"
                )
            }
            if !expectsKeys, !keys.isEmpty {
                throw GraphInspectionError.invalidDocument(
                    path: path,
                    reason: "provider '\(provider.id)' ordered collection has an unexpected key"
                )
            }
            if let duplicate = firstDuplicate(in: keys) {
                throw GraphInspectionError.invalidDocument(
                    path: path,
                    reason: "provider '\(provider.id)' repeats collection key '\(duplicate)'"
                )
            }
            for (index, entry) in collection.entries.enumerated() {
                guard entry.order == index else {
                    throw GraphInspectionError.invalidDocument(
                        path: path,
                        reason: "provider '\(provider.id)' collection order must be contiguous from zero"
                    )
                }
                guard let contributor = providersByID[entry.providerID],
                      contributor.containerID == provider.containerID else {
                    throw GraphInspectionError.invalidDocument(
                        path: path,
                        reason: "provider '\(provider.id)' collection contributor '\(entry.providerID)' is missing or belongs to another container"
                    )
                }
                guard entry.providerLifetime == contributor.lifetime else {
                    throw GraphInspectionError.invalidDocument(
                        path: path,
                        reason: "provider '\(provider.id)' collection contributor '\(entry.providerID)' has stale lifetime metadata"
                    )
                }
            }
        }
    }
}

private func firstDuplicate(in values: [String]) -> String? {
    var seen: Set<String> = []
    return values.first { !seen.insert($0).inserted }
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
    let addedProviderIDs: [String]
    let removedProviderIDs: [String]
    let changedProviders: [String]

    var hasChanges: Bool {
        beforeScope != afterScope
            || !addedNodeIDs.isEmpty
            || !removedNodeIDs.isEmpty
            || !changedNodes.isEmpty
            || !addedEdgeIDs.isEmpty
            || !removedEdgeIDs.isEmpty
            || !addedProviderIDs.isEmpty
            || !removedProviderIDs.isEmpty
            || !changedProviders.isEmpty
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
    let beforeProviders = Dictionary(
        before.providers.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    let afterProviders = Dictionary(
        after.providers.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )
    let beforeProviderIDs = Set(beforeProviders.keys)
    let afterProviderIDs = Set(afterProviders.keys)
    let changedProviders = beforeProviderIDs.intersection(afterProviderIDs)
        .filter {
            beforeProviders[$0]?.semanticIdentity
                != afterProviders[$0]?.semanticIdentity
        }
        .sorted()
        .map { id in
            guard let old = beforeProviders[id], let new = afterProviders[id]
            else { return id }
            return "\(id): \(providerChangeDescription(before: old, after: new))"
        }

    return GraphDiffReport(
        beforeScope: before.scope,
        afterScope: after.scope,
        addedNodeIDs: addedNodeIDs,
        removedNodeIDs: removedNodeIDs,
        changedNodes: changedNodes,
        addedEdgeIDs: afterEdgeIDs.subtracting(beforeEdgeIDs).sorted(),
        removedEdgeIDs: beforeEdgeIDs.subtracting(afterEdgeIDs).sorted(),
        addedProviderIDs: afterProviderIDs.subtracting(beforeProviderIDs).sorted(),
        removedProviderIDs: beforeProviderIDs.subtracting(afterProviderIDs).sorted(),
        changedProviders: changedProviders
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
        title: "Providers added",
        marker: "+",
        values: report.addedProviderIDs,
        to: &lines
    )
    appendDiffSection(
        title: "Providers removed",
        marker: "-",
        values: report.removedProviderIDs,
        to: &lines
    )
    appendDiffSection(
        title: "Providers changed",
        marker: "~",
        values: report.changedProviders,
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

private func providerChangeDescription(
    before: GraphJSON.Provider,
    after: GraphJSON.Provider
) -> String {
    var changes: [String] = []
    func append<T: Equatable>(_ label: String, _ old: T, _ new: T) {
        if old != new { changes.append("\(label) \(old) -> \(new)") }
    }
    append("type", before.type, after.type)
    append("role", before.role.rawValue, after.role.rawValue)
    append("lifetime", before.lifetime.rawValue, after.lifetime.rawValue)
    append("initialization", before.initialization.rawValue, after.initialization.rawValue)
    append("isolation", before.isolation.rawValue, after.isolation.rawValue)
    append("effect", before.effect.rawValue, after.effect.rawValue)
    append("inputKind", before.inputKind?.rawValue ?? "none", after.inputKind?.rawValue ?? "none")
    append("dependencies", before.dependencies, after.dependencies)
    append("dependencyBindings", before.dependencyBindings, after.dependencyBindings)
    append("containerBindings", before.containerBindings, after.containerBindings)
    append("collection", before.collection, after.collection)
    return changes.joined(separator: "; ")
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
