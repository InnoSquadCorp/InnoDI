import Testing

@testable import InnoDICore

@Suite("Shared stable initialization ordering")
struct StableInitializationOrderTests {
    @Test("Ready priority is original index, including newly ready nodes")
    func readyPriority() throws {
        let nodes: [InitializationOrderNode] = [
            .init(name: "a", hardDependencies: []),
            .init(name: "b", hardDependencies: ["a"]),
            .init(name: "c", hardDependencies: []),
        ]
        #expect(try stableInitializationOrder(nodes) == [0, 1, 2])
        #expect(try stableInitializationOrder([]).isEmpty)
    }

    @Test("Diamonds deduplicate edges and ignore names outside the stage")
    func diamondAndUnknownNames() throws {
        let nodes: [InitializationOrderNode] = [
            .init(name: "end", hardDependencies: ["left", "right", "input", "left"]),
            .init(name: "left", hardDependencies: ["root", "root"]),
            .init(name: "independent", hardDependencies: []),
            .init(name: "right", hardDependencies: ["root"]),
            .init(name: "root", hardDependencies: ["input"]),
        ]
        #expect(try stableInitializationOrder(nodes) == [2, 4, 1, 3, 0])
    }

    @Test("Only exact hard names participate; normalized fallback names do not")
    func exactNameEdges() throws {
        let nodes: [InitializationOrderNode] = [
            .init(name: "target", hardDependencies: ["later"]),
            .init(name: "consumer", hardDependencies: ["_storage_target"]),
            .init(name: "later", hardDependencies: []),
        ]
        #expect(try stableInitializationOrder(nodes) == [1, 2, 0])
    }

    @Test("Duplicate names and cycles fail without trapping")
    func invalidGraphs() {
        #expect(throws: InitializationOrderError.duplicateName("a")) {
            try stableInitializationOrder([
                .init(name: "a", hardDependencies: []),
                .init(name: "a", hardDependencies: []),
            ])
        }
        #expect(throws: InitializationOrderError.cycle) {
            try stableInitializationOrder([
                .init(name: "a", hardDependencies: ["b"]),
                .init(name: "b", hardDependencies: ["a"]),
            ])
        }
        #expect(throws: InitializationOrderError.cycle) {
            try stableInitializationOrder([.init(name: "a", hardDependencies: ["a"])])
        }
    }

    @Test("Sparse permuted DAGs agree with an independent minimum-ready reference", arguments: 0..<12)
    func permutedDAG(seed: Int) throws {
        let count = 80
        let ranks = (0..<count).map { ($0 * 37 + seed * 13) % count }
        let nodes = ranks.map { rank in
            InitializationOrderNode(
                name: "n\(rank)",
                hardDependencies: [rank - 1, rank - 7, rank - 13].filter { $0 >= 0 }.map { "n\($0)" }
            )
        }
        var remaining = Set(nodes.indices)
        var resolved = Set<String>()
        var expected: [Int] = []
        while !remaining.isEmpty {
            let next = try #require(remaining.sorted().first { index in
                nodes[index].hardDependencies.allSatisfy { resolved.contains($0) }
            })
            expected.append(next)
            resolved.insert(nodes[next].name)
            remaining.remove(next)
        }
        #expect(try stableInitializationOrder(nodes) == expected)
    }
}
