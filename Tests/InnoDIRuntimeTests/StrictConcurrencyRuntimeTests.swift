import Foundation
import Testing

import InnoDI

private struct SendablePayload: Sendable, Equatable {
    let value: Int
}

@Suite("Strict concurrency runtime surface")
struct StrictConcurrencyRuntimeTests {
    @Test("Lazy and Provider still resolve sendable payloads without sendability guarantees")
    func deferredWrappersResolveSendablePayloads() {
        let lazy = InnoDI.Lazy<SendablePayload> { SendablePayload(value: 1) }
        let provider = InnoDI.Provider<SendablePayload> { SendablePayload(value: 2) }

        #expect(lazy().value == 1)
        #expect(provider().value == 2)
    }
}

// MARK: - Storage concurrent-access stress tests

/// Identifier-bearing object used to detect distinct factory invocations.
final class StorageStressProbe: @unchecked Sendable {
    let id = UUID()
}

/// Records the number of times a factory closure runs. The lock guards the
/// counter under concurrent invocation; the test fails fast if a `.shared`
/// dependency runs its factory more than once.
final class StorageStressFactoryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func make() -> StorageStressProbe {
        lock.lock()
        _count += 1
        lock.unlock()
        return StorageStressProbe()
    }
}

/// Two `.input` counters keep the `.shared` factory invocation count
/// independent from the `.transient` invocation count. InnoDI runs `.shared`
/// factories eagerly at container init, so a single shared counter would
/// conflate one init-time invocation with the per-read transient counts
/// these tests are trying to measure.
@DIContainer
struct StorageStressContainer {
    @Provide(.input)
    var sharedCounter: StorageStressFactoryCounter

    @Provide(.input)
    var transientCounter: StorageStressFactoryCounter

    @Provide(.shared, factory: { (sharedCounter: StorageStressFactoryCounter) in sharedCounter.make() }, concrete: true)
    var sharedProbe: StorageStressProbe

    @Provide(.transient, factory: { (transientCounter: StorageStressFactoryCounter) in transientCounter.make() }, concrete: true)
    var transientProbe: StorageStressProbe
}

/// `@unchecked Sendable` box for the test container so we can hand the same
/// instance to concurrent detached tasks. The container is read-only after
/// initialization, which is the invariant these tests verify.
final class StorageStressContainerBox: @unchecked Sendable {
    let container: StorageStressContainer

    init(_ container: StorageStressContainer) {
        self.container = container
    }
}

/// Stress-tests the macro-synthesized `_storage_*` accessors under concurrent
/// reads. `.shared` must return the same instance to every caller and run the
/// factory exactly once; `.transient` must return a fresh instance every time
/// and the factory call count must equal the read count exactly.
///
/// These tests close the gap noted in the May 2026 review: the runtime suite
/// previously verified type-level concurrency only, leaving real concurrent
/// access of the synthesized storage cells uncovered.
@Suite("Storage concurrent access")
struct StorageConcurrentAccessTests {
    private static let iterations = 1024

    private static func makeContainer() -> (StorageStressContainerBox, shared: StorageStressFactoryCounter, transient: StorageStressFactoryCounter) {
        let sharedCounter = StorageStressFactoryCounter()
        let transientCounter = StorageStressFactoryCounter()
        let container = StorageStressContainer(
            sharedCounter: sharedCounter,
            transientCounter: transientCounter
        ) { _ in }
        return (StorageStressContainerBox(container), sharedCounter, transientCounter)
    }

    @Test(".shared accessor returns the same instance under concurrent reads")
    func sharedAccessorIdentityIsStable() async {
        let (box, shared, transient) = Self.makeContainer()

        let identifiers = await withTaskGroup(of: UUID.self, returning: [UUID].self) { group in
            for _ in 0..<Self.iterations {
                group.addTask { box.container.sharedProbe.id }
            }
            var collected: [UUID] = []
            collected.reserveCapacity(Self.iterations)
            for await id in group { collected.append(id) }
            return collected
        }

        #expect(identifiers.count == Self.iterations)
        #expect(Set(identifiers).count == 1)
        // Eager .shared init runs the factory exactly once, regardless of
        // how many concurrent reads follow.
        #expect(shared.count == 1)
        #expect(transient.count == 0)
    }

    @Test(".transient accessor produces a fresh instance for every concurrent read")
    func transientAccessorIdentityIsDistinct() async {
        let (box, shared, transient) = Self.makeContainer()

        let identifiers = await withTaskGroup(of: UUID.self, returning: [UUID].self) { group in
            for _ in 0..<Self.iterations {
                group.addTask { box.container.transientProbe.id }
            }
            var collected: [UUID] = []
            collected.reserveCapacity(Self.iterations)
            for await id in group { collected.append(id) }
            return collected
        }

        #expect(identifiers.count == Self.iterations)
        #expect(Set(identifiers).count == Self.iterations)
        #expect(transient.count == Self.iterations)
        // Eager .shared init still runs once even when no test reads sharedProbe.
        #expect(shared.count == 1)
    }

    @Test("Mixed concurrent .shared and .transient reads honor both contracts simultaneously")
    func mixedConcurrentReads() async {
        let (box, shared, transient) = Self.makeContainer()

        let half = Self.iterations / 2
        let result = await withTaskGroup(
            of: (kind: String, id: UUID).self,
            returning: (sharedIDs: Set<UUID>, transientIDs: Set<UUID>).self
        ) { group in
            for _ in 0..<half {
                group.addTask { ("shared", box.container.sharedProbe.id) }
                group.addTask { ("transient", box.container.transientProbe.id) }
            }
            var sharedIDs: Set<UUID> = []
            var transientIDs: Set<UUID> = []
            for await pair in group {
                if pair.kind == "shared" { sharedIDs.insert(pair.id) }
                else { transientIDs.insert(pair.id) }
            }
            return (sharedIDs, transientIDs)
        }

        #expect(result.sharedIDs.count == 1)
        #expect(result.transientIDs.count == half)
        #expect(shared.count == 1)
        #expect(transient.count == half)
    }
}
