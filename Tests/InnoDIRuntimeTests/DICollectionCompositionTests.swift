import Foundation
import Testing

@testable import InnoDI

private protocol CollectionService: Sendable { var name: String { get } }
private struct AlphaService: CollectionService { let name = "alpha" }
private struct BetaService: CollectionService { let name = "beta" }
private struct CollectionCatalog { var alpha: any CollectionService }
private struct SendableMetadataRoot: Sendable {
    var value: Int { 7 }
    subscript(index: Int) -> Int { value + index }
}

@Suite("DI collection composition")
struct DICollectionCompositionTests {
    @Test("Checked metadata preserves safe captured key paths across concurrent readers")
    func checkedMetadataConcurrentReaders() async {
        let paths: [AnyKeyPath & Sendable] = [\SendableMetadataRoot.value, \SendableMetadataRoot.[5]]
        let contributions = paths.enumerated().map {
            DIKeyedCollectionContribution(key: String($0.offset), contributor: $0.element)
        }
        let metadata: [DICollectionMetadata] = [
            .ordered(paths), .providers(paths), .keyed(contributions), .keyedProviders(contributions),
        ]
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for entry in metadata {
                        let stored = entry.contributors.isEmpty
                            ? entry.keyedContributors.map(\.contributor) : entry.contributors
                        for _ in 0..<1_000 {
                            let values = stored.map { SendableMetadataRoot()[keyPath: $0 as! KeyPath<SendableMetadataRoot, Int>] }
                            #expect(values == [7, 12])
                        }
                    }
                }
            }
        }
    }

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

    @Test("keyed collections keep an explicit empty contribution and miss absent keys")
    func keyedEmptyContribution() throws {
        let empty = DIKeyedCollection<String, Int>.empty
        let module = try DIKeyedCollection([
            DIKeyedCollection<String, Int>.Entry(key: "a", value: 1),
        ])
        let composed = try DIKeyedCollection.compose([empty, module, .empty])

        #expect(empty.isEmpty)
        #expect(empty[key: "a"] == nil)
        #expect(composed.map(\.key) == ["a"])
        #expect(composed[key: "missing"] == nil)
    }

    @Test("provider collections compose in order and resolve once per read")
    func providerComposition() {
        let counter = LockedCounter()
        let moduleA = DIProviderCollection<any CollectionService>([
            { counter.increment(0); return AlphaService() },
        ])
        let moduleB = DIProviderCollection<any CollectionService>([
            { counter.increment(1); return BetaService() },
        ])
        let composed = DIProviderCollection.compose([moduleA, .empty, moduleB])

        #expect(DIProviderCollection<any CollectionService>.empty.isEmpty)
        #expect(composed.count == 2)
        // Composition and counting resolve nothing.
        #expect(counter.snapshot() == [0, 0])
        #expect(composed.map(\.name) == ["alpha", "beta"])
        #expect(counter.snapshot() == [1, 1])
    }

    @Test("keyed provider collections compose, select by position, and reject collisions")
    func keyedProviderComposition() throws {
        let counter = LockedCounter()
        let moduleA = try DIKeyedProviderCollection([
            DIKeyedProviderCollection<String, Int>.Entry(key: "a") {
                counter.increment(0); return 1
            },
        ])
        let moduleB = try DIKeyedProviderCollection([
            DIKeyedProviderCollection<String, Int>.Entry(key: "b") {
                counter.increment(1); return 2
            },
        ])
        let composed = try DIKeyedProviderCollection.compose([moduleA, .empty, moduleB])

        #expect(DIKeyedProviderCollection<String, Int>.empty.isEmpty)
        #expect(composed.map(\.key) == ["a", "b"])
        #expect(composed[key: "missing"] == nil)
        // Reading keys and missing a lookup resolve nothing.
        #expect(counter.snapshot() == [0, 0])
        #expect(composed[1]() == 2)
        #expect(counter.snapshot() == [0, 1])

        #expect(throws: DIKeyedCollectionDuplicateError(key: "a")) {
            try DIKeyedProviderCollection.compose([composed, moduleA])
        }
        #expect(throws: DIKeyedCollectionDuplicateError(key: "b")) {
            try DIKeyedProviderCollection([
                DIKeyedProviderCollection<String, Int>.Entry(key: "b") { 1 },
                DIKeyedProviderCollection<String, Int>.Entry(key: "b") { 2 },
            ])
        }
        // A rejected composition resolves no provider.
        #expect(counter.snapshot() == [0, 1])
    }

    @Test("collection metadata preserves public kind key and contributor identity")
    func collectionMetadataContract() {
        let keyed = DICollectionMetadata.keyedProviders([
            .init(key: "alpha", contributor: \CollectionCatalog.alpha),
        ])
        let empty = DICollectionMetadata.ordered([])

        #expect(keyed.kind == .keyedProviders)
        #expect(keyed.contributors.isEmpty)
        #expect(keyed.keyedContributors.map(\.key) == ["alpha"])
        #expect(
            keyed.keyedContributors.first?.contributor
                == \CollectionCatalog.alpha
        )
        #expect(empty.kind == .ordered)
        #expect(empty.contributors.isEmpty)
        #expect(empty.keyedContributors.isEmpty)
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
