import Testing

@testable import InnoDICore

@Suite("DependencyCycleDetector")
struct DependencyCycleDetectorTests {
    @Test("Detects a simple 2-node cycle")
    func detectsSimpleCycle() throws {
        let adjacency: [String: [String]] = [
            "A": ["B"],
            "B": ["A"]
        ]

        let cycles = detectDependencyCycles(adjacency: adjacency)
        try #require(cycles.count == 1)
        #expect(cycles[0] == ["A", "B", "A"])
    }

    @Test("Returns no cycles for DAG")
    func noCyclesForDAG() {
        let adjacency: [String: [String]] = [
            "A": ["B", "C"],
            "B": ["D"],
            "C": ["D"],
            "D": []
        ]

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles.isEmpty)
    }

    @Test("Detects self cycle")
    func detectsSelfCycle() {
        let adjacency: [String: [String]] = [
            "A": ["A"]
        ]

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles == [["A", "A"]])
    }

    @Test("Reports deterministic witnesses instead of enumerating overlapping elementary cycles")
    func overlappingCyclesUseWitnessContract() {
        let adjacency: [String: [String]] = [
            "A": ["B", "C"],
            "B": ["C"],
            "C": ["A"]
        ]

        // The graph contains A-B-C-A and A-C-A. DAG validation needs a
        // deterministic proof of cyclicity, not an exponential enumeration.
        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles == [["A", "B", "C", "A"]])
    }

    @Test("Rotates every witness to its lexicographically smallest node")
    func canonicalizesReportedWitness() {
        let adjacency: [String: [String]] = [
            "A": ["Z"],
            "Z": ["B"],
            "B": ["Z"]
        ]

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles == [["B", "Z", "B"]])
    }
}
