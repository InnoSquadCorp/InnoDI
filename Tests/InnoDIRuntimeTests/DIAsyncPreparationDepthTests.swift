import InnoDI
import Testing

private actor PreparationOrder {
    var events: [String] = []
    func append(_ event: String) { events.append(event) }
}

private struct DepthProvider: DIAsyncPreparing {
    let providerID: String
    var order: PreparationOrder?
    func status() async -> DIAsyncProviderStatus {
        .init(providerID: providerID, generation: 0, state: .ready)
    }
    func prepare() async -> DIAsyncProviderStatus {
        await order?.append("prepare:\(providerID)")
        return await status()
    }
    func retry() async throws {}
    func close() async { await order?.append("close:\(providerID)") }
}

@Suite("Preparation graph depth and ordering")
struct DIAsyncPreparationDepthTests {
    @Test("Valid long chains use heap traversal", arguments: [1, 1_000, 5_000, 20_000])
    func longChain(count: Int) async throws {
        let plan = try DIAsyncPreparationPlan(nodes: (0..<count).map { index in
            .init(provider: DepthProvider(providerID: String(index)),
                  dependencies: index + 1 < count ? [String(index + 1)] : [])
        })
        let report = try await plan.prepare(["0"])
        #expect(report.entries.map(\.providerID) == (0..<count).reversed().map(String.init))
        try await plan.close(["0"])
    }

    @Test("Deep back edges and self cycles return their exact path", arguments: [1, 20_000])
    func deepCycle(count: Int) {
        #expect(throws: DIAsyncPreparationPlanError.dependencyCycle((0..<count).map(String.init) + ["0"])) {
            _ = try DIAsyncPreparationPlan(nodes: (0..<count).map { index in
                .init(provider: DepthProvider(providerID: String(index)),
                      dependencies: [String((index + 1) % count)])
            })
        }
    }

    @Test("Diamond traversal preserves declaration order and reversed close order")
    func diamondOrder() async throws {
        let order = PreparationOrder()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: DepthProvider(providerID: "root", order: order), dependencies: ["left", "right"]),
            .init(provider: DepthProvider(providerID: "right", order: order), dependencies: ["leaf"]),
            .init(provider: DepthProvider(providerID: "left", order: order), dependencies: ["leaf", "leaf"]),
            .init(provider: DepthProvider(providerID: "leaf", order: order)),
        ])
        _ = try await plan.prepare(["root"])
        try await plan.close(["root"])
        #expect(await order.events == ["prepare:leaf", "prepare:left", "prepare:right", "prepare:root",
                                      "close:root", "close:right", "close:left", "close:leaf"])
    }

    @Test("Empty and wide disconnected graphs remain valid")
    func emptyAndWide() async throws {
        let empty = try DIAsyncPreparationPlan(nodes: [])
        #expect(try await empty.prepare([]).entries.isEmpty)
        let ids = (0..<1_000).map(String.init)
        let wide = try DIAsyncPreparationPlan(nodes: ids.map { .init(provider: DepthProvider(providerID: $0)) })
        #expect(try await wide.prepare(ids).entries.map(\.providerID) == ids)
    }
}
