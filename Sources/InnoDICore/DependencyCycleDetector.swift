import Foundation

/// Cycle detection output, including whether any branch was skipped because
/// it reached the configured depth limit.
public struct DependencyCycleDetectionResult: Equatable, Sendable {
    /// Deterministic cycle witnesses discovered by DFS.
    ///
    /// This is intentionally not an enumeration of every elementary cycle:
    /// the number of elementary cycles can grow exponentially with graph
    /// size. When `truncatedByDepthLimit` is `false`, an empty array proves
    /// that the graph is acyclic; a non-empty array proves that it is cyclic.
    public let cycles: [[String]]

    /// Whether the depth bound prevented a complete DAG validation.
    public let truncatedByDepthLimit: Bool

    public init(cycles: [[String]], truncatedByDepthLimit: Bool) {
        self.cycles = cycles
        self.truncatedByDepthLimit = truncatedByDepthLimit
    }
}

/// Deterministic cycle detection on directed graphs.
///
/// Implementation notes:
/// - Iterative DFS with an explicit frame stack (no recursion), so pathological
///   graphs cannot blow the native call stack.
/// - Neighbors are visited in sorted order to keep the reported cycle list
///   stable across runs.
/// - Each DFS back edge produces a cycle witness. Witnesses are deduplicated
///   and rotated to the lexicographically smallest representation.
/// - Witnesses are deliberately non-exhaustive. Enumerating every elementary
///   cycle can require exponential time and memory, while DAG validation only
///   needs a proof that at least one cycle exists.
/// - Reports whether any traversal branch was abandoned because it exceeded
///   the configured depth limit.
///
/// - Parameters:
///   - adjacency: Adjacency list where each key is a node id and each value
///     is a list of destination node ids.
///   - depthLimit: Maximum explicit-stack depth before a traversal branch is
///     abandoned. Defaults to 4096 — far beyond the depth of any realistic
///     DI graph but cheap enough to bound adversarial input.
/// - Returns: Deterministic cycle witnesses plus truncation metadata. Each
///   witness is returned as `A -> ... -> A`. If the result is not truncated,
///   `cycles.isEmpty` is equivalent to the graph being acyclic.
public func analyzeDependencyCycles(
    adjacency: [String: [String]],
    depthLimit: Int = 4096
) -> DependencyCycleDetectionResult {
    let effectiveDepthLimit = max(1, depthLimit)
    let allNodes = Set(adjacency.keys).union(adjacency.values.flatMap { $0 })
    let sortedNodes = allNodes.sorted()

    var state: [String: VisitState] = [:]
    var pathStack: [String] = []
    var indexByNode: [String: Int] = [:]
    var cycles: [[String]] = []
    var seenCanonical: Set<String> = []
    var truncatedByDepthLimit = false

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
                let canonicalCore = canonicalCycleCore(cycleCore)
                let canonicalKey = canonicalCore.joined(separator: "->")
                if seenCanonical.insert(canonicalKey).inserted,
                   let firstNode = canonicalCore.first {
                    cycles.append(canonicalCore + [firstNode])
                }

            case .visited:
                continue iterative

            case .none:
                // Depth-limit guard: if the explicit stack has grown past the
                // configured ceiling, abandon this branch instead of descending
                // further. The traversal state stays consistent — we simply
                // treat the deeper edge as unexplored.
                if frames.count >= effectiveDepthLimit {
                    truncatedByDepthLimit = true
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

    let sortedCycles = cycles.sorted { lhs, rhs in
        lhs.joined(separator: "->") < rhs.joined(separator: "->")
    }
    return DependencyCycleDetectionResult(
        cycles: sortedCycles,
        truncatedByDepthLimit: truncatedByDepthLimit
    )
}

/// Deterministic cycle detection on directed graphs.
///
/// - Returns: Non-exhaustive cycle witnesses. Each witness is returned as
///   `A -> ... -> A`. An empty result proves the graph is acyclic only when
///   the corresponding analysis would not be truncated by `depthLimit`.
public func detectDependencyCycles(
    adjacency: [String: [String]],
    depthLimit: Int = 4096
) -> [[String]] {
    analyzeDependencyCycles(adjacency: adjacency, depthLimit: depthLimit).cycles
}

private enum VisitState {
    case visiting
    case visited
}

/// Returns the lexicographically smallest rotation of the cycle core.
///
/// DFS cycle witnesses contain no repeated internal nodes, so the minimum
/// rotation is anchored at the smallest node id — a single linear scan
/// identifies it in O(n). If a witness ever contained repeats (not expected
/// for DI graphs), this still produces a canonical ordering via tie breaking
/// on subsequent elements.
private func canonicalCycleCore(_ cycleCore: [String]) -> [String] {
    guard !cycleCore.isEmpty else { return [] }
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
    return rotated
}
