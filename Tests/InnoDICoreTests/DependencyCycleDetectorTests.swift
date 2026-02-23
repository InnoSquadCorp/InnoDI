import Testing

@testable import InnoDICore

@Suite("DependencyCycleDetector")
struct DependencyCycleDetectorTests {
    @Test("Detects a simple 2-node cycle")
    func detectsSimpleCycle() {
        let adjacency: [String: [String]] = [
            "A": ["B"],
            "B": ["A"]
        ]

        let cycles = detectDependencyCycles(adjacency: adjacency)
        #expect(cycles.count == 1)
        #expect(cycles[0] == ["A", "B", "A"] || cycles[0] == ["B", "A", "B"])
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
}
