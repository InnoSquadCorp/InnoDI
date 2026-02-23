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
}
