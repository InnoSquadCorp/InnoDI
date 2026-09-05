import Foundation
import Testing

@testable import InnoDI

private protocol CollectionService: Sendable { var name: String { get } }
private struct AlphaService: CollectionService { let name = "alpha" }
private struct BetaService: CollectionService { let name = "beta" }

@Suite("DI collection composition")
struct DICollectionCompositionTests {
    @Test("ordered groups compose explicitly and preserve empty semantics")
    func orderedComposition() {
        let moduleA = DICollectionGroup<any CollectionService>([AlphaService()])
        let moduleB = DICollectionGroup<any CollectionService>([BetaService()])
        let composed = DICollectionGroup.compose([moduleA, .empty, moduleB])

        #expect(composed.map(\.name) == ["alpha", "beta"])
        #expect(DICollectionGroup<any CollectionService>.empty.isEmpty)
    }

    @Test("keyed composition preserves order and rejects nested collisions")
    func keyedComposition() throws {
        let moduleA = try DIKeyedCollection([
            DIKeyedCollection<String, Int>.Entry(key: "a", value: 1),
        ])
        let moduleB = try DIKeyedCollection([
            DIKeyedCollection<String, Int>.Entry(key: "b", value: 2),
        ])
        let composed = try DIKeyedCollection.compose([moduleA, moduleB])

        #expect(composed.map(\.key) == ["a", "b"])
        #expect(composed[key: "b"] == 2)
        #expect(throws: DIKeyedCollectionDuplicateError(key: "a")) {
            try DIKeyedCollection.compose([composed, moduleA])
        }
    }

    @Test("provider collections resolve only selected entries")
    func providerSelectionIsLazy() throws {
        let counter = LockedCounter()
        let providers = DIProviderCollection<any CollectionService>([
            { counter.increment(0); return AlphaService() },
            { counter.increment(1); return BetaService() },
        ])

        #expect(providers[1].name == "beta")
        #expect(counter.snapshot() == [0, 1])

        let keyed = try DIKeyedProviderCollection([
            DIKeyedProviderCollection<String, Int>.Entry(key: "a") {
                counter.increment(0); return 1
            },
            DIKeyedProviderCollection<String, Int>.Entry(key: "b") {
                counter.increment(1); return 2
            },
        ])
        #expect(keyed[key: "a"] == 1)
        #expect(counter.snapshot() == [1, 1])
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [0, 0]

    func increment(_ index: Int) {
        lock.lock()
        values[index] += 1
        lock.unlock()
    }

    func snapshot() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
