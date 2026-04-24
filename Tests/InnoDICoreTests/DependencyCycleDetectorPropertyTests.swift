import Testing

import InnoDITestSupport
@testable import InnoDICore

@Suite("DependencyCycleDetector Property Tests")
struct DependencyCycleDetectorPropertyTests {
    @Test("Acyclic generated graphs do not produce false positives", arguments: Array(0..<200))
    func acyclicGraphsRemainAcyclic(seed: Int) {
        var rng = SeededRandom(seed: UInt64(seed + 1000))
        let count = 4 + rng.nextInt(upperBound: 6)
        let nodes = (0..<count).map { "N\($0)" }
        var adjacency: [String: [String]] = [:]

        for from in 0..<count {
            var neighbors: [String] = []
            for to in (from + 1)..<count where rng.nextBool() {
                neighbors.append(nodes[to])
            }
            adjacency[nodes[from]] = neighbors
        }

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles.isEmpty)
    }

    @Test("Cyclic generated graphs always report at least one cycle", arguments: Array(0..<200))
    func cyclicGraphsAlwaysDetected(seed: Int) {
        var rng = SeededRandom(seed: UInt64(seed + 5000))
        let count = 3 + rng.nextInt(upperBound: 4)
        let nodes = (0..<count).map { "C\($0)" }
        var adjacency: [String: [String]] = [:]

        for index in 0..<count {
            let next = (index + 1) % count
            adjacency[nodes[index], default: []].append(nodes[next])

            if rng.nextBool() {
                let extra = rng.nextInt(upperBound: count)
                if extra != index {
                    adjacency[nodes[index], default: []].append(nodes[extra])
                }
            }
        }

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(!cycles.isEmpty)
        #expect(cycles.allSatisfy { cycle in cycle.count >= 2 && cycle.first == cycle.last })
    }

    @Test("Results are deterministic across runs on the same seed", arguments: Array(0..<50))
    func resultsAreDeterministic(seed: Int) {
        var rng = SeededRandom(seed: UInt64(seed + 9000))
        let count = 3 + rng.nextInt(upperBound: 5)
        let nodes = (0..<count).map { "D\($0)" }

        // Deterministic adjacency from a mix of acyclic and cyclic edges.
        var adjacency: [String: [String]] = [:]
        for from in 0..<count {
            var neighbors: [String] = []
            for to in 0..<count where from != to && rng.nextBool() {
                neighbors.append(nodes[to])
            }
            adjacency[nodes[from]] = neighbors
        }

        let first = detectDependencyCycles(adjacency: adjacency)
        let second = detectDependencyCycles(adjacency: adjacency)
        let third = detectDependencyCycles(adjacency: adjacency)

        #expect(first == second)
        #expect(second == third)
    }

    @Test("Every reported cycle starts and ends at the same node")
    func everyCycleIsClosed() {
        let adjacency = [
            "A": ["B"],
            "B": ["C"],
            "C": ["A", "D"],
            "D": ["E"],
            "E": ["D", "F"],
            "F": [] as [String]
        ]

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(!cycles.isEmpty)
        for cycle in cycles {
            #expect(cycle.count >= 2)
            #expect(cycle.first == cycle.last, "Cycle '\(cycle)' is not closed")
        }
    }

    @Test("Depth limit abandons traversal without crashing")
    func depthLimitIsHonored() {
        // A long acyclic chain deeper than the depth limit would have
        // recursed without bound in the old implementation. With an explicit
        // stack and depth cap, the detector simply returns an empty list.
        let chainLength = 5_000
        var adjacency: [String: [String]] = [:]
        for index in 0..<(chainLength - 1) {
            adjacency["node\(index)"] = ["node\(index + 1)"]
        }
        adjacency["node\(chainLength - 1)"] = []

        let cycles = detectDependencyCycles(adjacency: adjacency, depthLimit: 256)
        #expect(cycles.isEmpty)
    }

    @Test("Self-loops are reported once")
    func selfLoopIsReportedOnce() {
        let adjacency = ["Self": ["Self"]]
        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles.count == 1)
        #expect(cycles.first?.first == "Self")
        #expect(cycles.first?.last == "Self")
    }
}
