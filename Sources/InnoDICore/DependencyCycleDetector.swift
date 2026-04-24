import Foundation

/// Deterministic cycle detection on directed graphs.
///
/// Implementation notes:
/// - Iterative DFS with an explicit frame stack (no recursion), so pathological
///   graphs cannot blow the native call stack.
/// - Neighbors are visited in sorted order to keep the reported cycle list
///   stable across runs.
/// - Each distinct elementary cycle is reported once, keyed by the
///   lexicographically smallest rotation of its core path.
/// - The linear-in-cycle-length canonical rotation relies on cycles over
///   distinct nodes — which is an invariant of elementary cycles in a
///   dependency graph.
///
/// - Parameters:
///   - adjacency: Adjacency list where each key is a node id and each value
///     is a list of destination node ids.
///   - depthLimit: Maximum explicit-stack depth before a traversal branch is
///     abandoned. Defaults to 4096 — far beyond the depth of any realistic
///     DI graph but cheap enough to bound adversarial input.
/// - Returns: Unique cycle paths. Each cycle is returned as `A -> ... -> A`.
public func detectDependencyCycles(
    adjacency: [String: [String]],
    depthLimit: Int = 4096
) -> [[String]] {
    let allNodes = Set(adjacency.keys).union(adjacency.values.flatMap { $0 })
    let sortedNodes = allNodes.sorted()

    var state: [String: VisitState] = [:]
    var pathStack: [String] = []
    var indexByNode: [String: Int] = [:]
    var cycles: [[String]] = []
    var seenCanonical: Set<String> = []

    // An explicit DFS frame. `neighbors` is sorted up-front so each step just
    // advances `nextNeighborIndex`.
    struct Frame {
        let node: String
        let neighbors: [String]
        var nextNeighborIndex: Int
    }
    var frames: [Frame] = []

    func startTraversal(from root: String) {
        state[root] = .visiting
        indexByNode[root] = pathStack.count
        pathStack.append(root)
        frames.append(Frame(
            node: root,
            neighbors: (adjacency[root] ?? []).sorted(),
            nextNeighborIndex: 0
        ))
    }

    func finishTopFrame() {
        let finished = frames.removeLast()
        _ = pathStack.popLast()
        indexByNode[finished.node] = nil
        state[finished.node] = .visited
    }

    for root in sortedNodes where state[root] == nil {
        startTraversal(from: root)

        iterative: while !frames.isEmpty {
            let topIndex = frames.count - 1
            guard frames[topIndex].nextNeighborIndex < frames[topIndex].neighbors.count else {
                finishTopFrame()
                continue iterative
            }

            let neighbor = frames[topIndex].neighbors[frames[topIndex].nextNeighborIndex]
            frames[topIndex].nextNeighborIndex += 1

            switch state[neighbor] {
            case .visiting:
                let startIndex: Int
                if let mappedIndex = indexByNode[neighbor] {
                    startIndex = mappedIndex
                } else if let recoveredIndex = pathStack.firstIndex(of: neighbor) {
                    assertionFailure(
                        "DependencyCycleDetector invariant violated: missing indexByNode for visiting neighbor '\(neighbor)'; " +
                        "state=\(String(describing: state[neighbor])), indexByNode=\(indexByNode)"
                    )
                    startIndex = recoveredIndex
                } else {
                    assertionFailure(
                        "DependencyCycleDetector invariant violated: visiting neighbor '\(neighbor)' not found in stack; " +
                        "state=\(String(describing: state[neighbor])), indexByNode=\(indexByNode), stack=\(pathStack)"
                    )
                    continue iterative
                }

                let cycleCore = Array(pathStack[startIndex...])
                let cycle = cycleCore + [neighbor]
                let canonical = canonicalCycleString(cycleCore)
                if seenCanonical.insert(canonical).inserted {
                    cycles.append(cycle)
                }

            case .visited:
                continue iterative

            case .none:
                // Depth-limit guard: if the explicit stack has grown past the
                // configured ceiling, abandon this branch instead of descending
                // further. The traversal state stays consistent — we simply
                // treat the deeper edge as unexplored.
                if frames.count >= depthLimit {
                    continue iterative
                }
                state[neighbor] = .visiting
                indexByNode[neighbor] = pathStack.count
                pathStack.append(neighbor)
                frames.append(Frame(
                    node: neighbor,
                    neighbors: (adjacency[neighbor] ?? []).sorted(),
                    nextNeighborIndex: 0
                ))
            }
        }
    }

    return cycles.sorted { lhs, rhs in
        lhs.joined(separator: "->") < rhs.joined(separator: "->")
    }
}

private enum VisitState {
    case visiting
    case visited
}

/// Returns the lexicographically smallest rotation of the cycle core joined
/// with `->`.
///
/// Elementary cycles in a dependency graph contain no repeated nodes, so the
/// minimum rotation is anchored at the smallest node id — a single linear
/// scan identifies it in O(n). If the cycle ever contained repeats (not
/// expected for DI graphs), this still produces a canonical ordering via tie
/// breaking on subsequent elements.
private func canonicalCycleString(_ cycleCore: [String]) -> String {
    guard !cycleCore.isEmpty else { return "" }
    let size = cycleCore.count

    var minIndex = 0
    for i in 1..<size {
        if cycleCore[i] < cycleCore[minIndex] {
            minIndex = i
        } else if cycleCore[i] == cycleCore[minIndex] {
            // Tie: compare subsequent rotated elements until one side wins.
            for offset in 1..<size {
                let a = cycleCore[(i + offset) % size]
                let b = cycleCore[(minIndex + offset) % size]
                if a < b {
                    minIndex = i
                    break
                }
                if a > b {
                    break
                }
            }
        }
    }

    var rotated: [String] = []
    rotated.reserveCapacity(size)
    for offset in 0..<size {
        rotated.append(cycleCore[(minIndex + offset) % size])
    }
    return rotated.joined(separator: "->")
}
