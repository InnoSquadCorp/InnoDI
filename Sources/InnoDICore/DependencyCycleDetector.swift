import Foundation

/// Deterministic cycle detection on directed graphs.
///
/// - Parameter adjacency: Adjacency list where each key is a node id and each value
///   is a list of destination node ids.
/// - Returns: Unique cycle paths. Each cycle is returned as `A -> ... -> A`.
public func detectDependencyCycles(adjacency: [String: [String]]) -> [[String]] {
    let allNodes = Set(adjacency.keys).union(adjacency.values.flatMap { $0 })
    let sortedNodes = allNodes.sorted()

    var state: [String: VisitState] = [:]
    var stack: [String] = []
    var indexByNode: [String: Int] = [:]
    var cycles: [[String]] = []
    var seenCanonical: Set<String> = []

    func dfs(_ node: String) {
        state[node] = .visiting
        indexByNode[node] = stack.count
        stack.append(node)

        let neighbors = (adjacency[node] ?? []).sorted()
        for neighbor in neighbors {
            if state[neighbor] == .visiting {
                let startIndex: Int
                if let mappedIndex = indexByNode[neighbor] {
                    startIndex = mappedIndex
                } else if let recoveredIndex = stack.firstIndex(of: neighbor) {
                    assertionFailure(
                        "DependencyCycleDetector invariant violated: missing indexByNode for visiting neighbor '\(neighbor)'; " +
                        "state=\(String(describing: state[neighbor])), indexByNode=\(indexByNode)"
                    )
                    startIndex = recoveredIndex
                } else {
                    assertionFailure(
                        "DependencyCycleDetector invariant violated: visiting neighbor '\(neighbor)' not found in stack; " +
                        "state=\(String(describing: state[neighbor])), indexByNode=\(indexByNode), stack=\(stack)"
                    )
                    continue
                }

                let cycleCore = Array(stack[startIndex...])
                let cycle = cycleCore + [neighbor]
                let canonical = canonicalCycleString(cycleCore)
                if seenCanonical.insert(canonical).inserted {
                    cycles.append(cycle)
                }
                continue
            }

            if state[neighbor] == .visited {
                continue
            }

            dfs(neighbor)
        }

        _ = stack.popLast()
        indexByNode[node] = nil
        state[node] = .visited
    }

    for node in sortedNodes where state[node] == nil {
        dfs(node)
    }

    return cycles.sorted { lhs, rhs in
        lhs.joined(separator: "->") < rhs.joined(separator: "->")
    }
}

private enum VisitState {
    case visiting
    case visited
}

private func canonicalCycleString(_ cycleCore: [String]) -> String {
    guard !cycleCore.isEmpty else { return "" }
    let size = cycleCore.count
    var best: [String]? = nil

    for offset in 0..<size {
        var rotated: [String] = []
        rotated.reserveCapacity(size)
        for index in 0..<size {
            rotated.append(cycleCore[(offset + index) % size])
        }

        if best == nil || rotated.lexicographicallyPrecedes(best!) {
            best = rotated
        }
    }

    return (best ?? cycleCore).joined(separator: "->")
}
