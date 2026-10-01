import Foundation
import InnoDI
import Testing

// Pins the lifetime of `@Provide(.shared, initialization: .onDemand,
// asyncFactory:)`: nothing starts before the first read, concurrent readers
// share one construction, a cancelled reader leaves construction running,
// and `closeAsyncProviders()` cancels work and closes the provider.

struct AsyncOnDemandResource: Equatable, Sendable {
    let generation: Int
}

struct AsyncOnDemandFailure: Error, Equatable {}

final class TrackedAsyncOnDemandValue: Sendable {}

actor AsyncOnDemandAttemptCounter {
    private(set) var attempts = 0

    func record() {
        attempts += 1
    }
}

@DIContainer
struct AsyncOnDemandContainer {
    @Input var probe: EagerAsyncProbe

    @Provide(.shared, initialization: .onDemand, asyncFactory: { (probe: EagerAsyncProbe) async in
        await probe.recordStart()
        await probe.waitForGate()
        await probe.recordCompletion(cancelled: Task.isCancelled)
        return AsyncOnDemandResource(generation: await probe.startCount())
    })
    var resource: AsyncOnDemandResource
}

@DIContainer
struct FailingAsyncOnDemandContainer {
    @Input var counter: AsyncOnDemandAttemptCounter

    @Provide(
        .shared,
        initialization: .onDemand,
        asyncFactory: { (counter: AsyncOnDemandAttemptCounter) async throws -> AsyncOnDemandResource in
            await counter.record()
            throw AsyncOnDemandFailure()
        }
    )
    var resource: AsyncOnDemandResource
}

@DIContainer
struct AsyncOnDemandParent {
    @Input var probe: EagerAsyncProbe

    @SubContainer(scope: .transient)
    var child: AsyncOnDemandContainer
}

@DIContainer
struct AsyncOnDemandEagerConsumerContainer {
    @Input var probe: EagerAsyncProbe

    @Provide(.shared, initialization: .onDemand, asyncFactory: { (probe: EagerAsyncProbe) async in
        await probe.recordStart()
        await probe.waitForGate()
        return AsyncOnDemandResource(generation: await probe.startCount())
    })
    var resource: AsyncOnDemandResource

    @Provide(.shared, asyncFactory: { (resource: AsyncOnDemandResource) async throws in
        resource.generation
    })
    var generation: Int

    @Provide(.transient, asyncFactory: { (resource: AsyncOnDemandResource) async throws in
        resource.generation + 100
    })
    var offsetGeneration: Int
}

/// Deliberately non-`Sendable`; only a main-actor factory may capture it.
final class MainActorAsyncOnDemandCounter {
    var reads = 0
    var ranOnMainActor = false
}

/// Callable without `await` only from main-actor-isolated code, so the
/// factory below compiles only when its generated operation keeps it there.
@MainActor
func markMainActorAsyncOnDemandRead(_ counter: MainActorAsyncOnDemandCounter) {
    counter.ranOnMainActor = true
}

@DIContainerRole(role: ContainerRole.local, mainActor: true)
struct MainActorAsyncOnDemandContainer {
    @Input var counter: MainActorAsyncOnDemandCounter

    @Provide(.shared, initialization: .onDemand, asyncFactory: { (counter: MainActorAsyncOnDemandCounter) async in
        counter.reads += 1
        markMainActorAsyncOnDemandRead(counter)
        return counter.reads
    })
    var reads: Int
}

@Suite("Async on-demand shared provider lifetime", .timeLimit(.minutes(1)))
struct AsyncOnDemandProviderTests {
    private static let closed = DIAsyncScopeError.closed(providerID: "resource")

    @Test("Initialization starts nothing before the first read")
    func initializationStartsNothing() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe)
        for _ in 0..<50 { await Task.yield() }
        #expect(await probe.startCount() == 0)

        await probe.openGate()
        #expect(try await container.resource == AsyncOnDemandResource(generation: 1))
        #expect(await probe.startCount() == 1)
    }

    @Test("Concurrent readers share one construction")
    func concurrentReadersShareOneConstruction() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe)
        let readers = (0..<10).map { _ in
            Task { try await container.resource }
        }

        await probe.waitForStarts(1)
        await probe.openGate()
        for reader in readers {
            #expect(try await reader.value == AsyncOnDemandResource(generation: 1))
        }
        #expect(await probe.startCount() == 1)
    }

    @Test("Cancelling a reader leaves construction running for other readers")
    func cancellingReaderLeavesConstructionRunning() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe)
        let cancelled = Task { try await container.resource }

        await probe.waitForStarts(1)
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { try await cancelled.value }

        await probe.openGate()
        #expect(await probe.waitForCompletions(1) == [false])
        #expect(try await container.resource == AsyncOnDemandResource(generation: 1))
        #expect(await probe.startCount() == 1)
    }

    @Test("closeAsyncProviders cancels construction and closes the provider")
    func closeCancelsConstructionAndClosesProvider() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe)
        let waiting = Task { try await container.resource }

        await probe.waitForStarts(1)
        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await waiting.value }

        await probe.openGate()
        #expect(await probe.waitForCompletions(1) == [true])
        await #expect(throws: Self.closed) { try await container.resource }
        #expect(await probe.startCount() == 1)

        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await container.resource }
    }

    @Test("Closing before the first read prevents construction")
    func closeBeforeReadPreventsConstruction() async {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe)

        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await container.resource }
        #expect(await probe.startCount() == 0)
    }

    @Test("A failure is cached like an eager async provider failure")
    func failureIsCached() async {
        let counter = AsyncOnDemandAttemptCounter()
        let container = FailingAsyncOnDemandContainer(counter: counter)

        await #expect(throws: AsyncOnDemandFailure()) { try await container.resource }
        await #expect(throws: AsyncOnDemandFailure()) { try await container.resource }
        #expect(await counter.attempts == 1)
    }

    @Test("An override completes the provider without running the factory")
    func overrideSkipsFactory() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe) { overrides in
            overrides.resource = AsyncOnDemandResource(generation: 42)
        }

        #expect(try await container.resource == AsyncOnDemandResource(generation: 42))
        #expect(await probe.startCount() == 0)
    }

    @Test("Closing an overridden provider closes it like a constructed one")
    func closingOverrideMatchesProduction() async throws {
        let container = AsyncOnDemandContainer(probe: EagerAsyncProbe()) { overrides in
            overrides.resource = AsyncOnDemandResource(generation: 42)
        }

        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await container.resource }
        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await container.resource }
    }

    @Test("Closing after construction closes a ready provider")
    func closingReadyProvider() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandContainer(probe: probe)
        await probe.openGate()
        #expect(try await container.resource == AsyncOnDemandResource(generation: 1))

        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await container.resource }
        #expect(await probe.startCount() == 1)
    }

    @Test("Container copies share one provider and one close")
    func copiesShareProvider() async throws {
        let probe = EagerAsyncProbe()
        let original = AsyncOnDemandContainer(probe: probe)
        let copy = original

        await probe.openGate()
        #expect(try await copy.resource == AsyncOnDemandResource(generation: 1))
        #expect(try await original.resource == AsyncOnDemandResource(generation: 1))
        #expect(await probe.startCount() == 1)

        await copy.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await original.resource }
    }

    @Test("Reading a transient sub-container a hundred times starts nothing")
    func transientSubContainerReadsStartNothing() async throws {
        let probe = EagerAsyncProbe()
        let parent = AsyncOnDemandParent(probe: probe)

        for _ in 0..<100 {
            _ = parent.child
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(await probe.startCount() == 0)

        await probe.openGate()
        let child = parent.child
        #expect(try await child.resource == AsyncOnDemandResource(generation: 1))
        #expect(await probe.startCount() == 1)
    }

    @Test("An eager async consumer forces its on-demand dependency during initialization")
    func eagerConsumerForcesDependency() async throws {
        let probe = EagerAsyncProbe()
        let container = AsyncOnDemandEagerConsumerContainer(probe: probe)

        await probe.waitForStarts(1)
        await probe.openGate()
        #expect(try await container.generation == 1)
        #expect(try await container.offsetGeneration == 101)
        #expect(try await container.resource == AsyncOnDemandResource(generation: 1))
        #expect(await probe.startCount() == 1)
    }

    @Test("A main-actor container runs the factory on the main actor")
    @MainActor
    func mainActorFactoryRunsOnMainActor() async throws {
        let counter = MainActorAsyncOnDemandCounter()
        let container = MainActorAsyncOnDemandContainer(counter: counter)
        #expect(counter.reads == 0)

        #expect(try await container.reads == 1)
        #expect(try await container.reads == 1)
        #expect(counter.ranOnMainActor)

        await container.closeAsyncProviders()
        await #expect(throws: DIAsyncScopeError.closed(providerID: "reads")) {
            try await container.reads
        }
    }

    @Test("Tracing records construction, waits, and cache hits")
    func tracingRecordsLifecycle() async throws {
        let probe = EagerAsyncProbe()
        let buffer = DIBoundedTraceBuffer(capacity: 64)
        let container = AsyncOnDemandContainer(
            probe: probe,
            _innoDITrace: DITraceContext(sink: buffer)
        )
        #expect(buffer.snapshot().events.isEmpty)

        let first = Task { try await container.resource }
        await probe.waitForStarts(1)
        let second = Task { try await container.resource }
        while !buffer.snapshot().events.contains(where: { $0.kind == .waitStart }) {
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        await probe.openGate()
        _ = try await first.value
        _ = try await second.value
        _ = try await container.resource

        let events = buffer.snapshot().events
        #expect(events.map(\.kind) == [.start, .waitStart, .success, .waitEnd, .cacheHit, .cacheHit])
        #expect(Set(events.map(\.instanceID)).count == 1)
    }

    @Test("Closing releases a constructed or overridden value")
    func closeReleasesValue() async throws {
        weak var constructed: TrackedAsyncOnDemandValue?
        let constructedCell = _InnoDIAsyncSharedCell(
            traceOwner: .disabled,
            providerName: "resource",
            operation: { TrackedAsyncOnDemandValue() }
        )
        constructed = try await constructedCell.value()
        #expect(constructed != nil)

        weak var overridden: TrackedAsyncOnDemandValue?
        var value: TrackedAsyncOnDemandValue? = TrackedAsyncOnDemandValue()
        overridden = value
        let overrideCell = _InnoDIAsyncSharedCell(
            traceOwner: .disabled,
            providerName: "resource",
            value: value!
        )
        value = nil
        #expect(overridden != nil)

        await constructedCell.close()
        await overrideCell.close()
        #expect(constructed == nil)
        #expect(overridden == nil)
        await #expect(throws: Self.closed) { try await overrideCell.value() }
    }

    @Test("A construction that finishes after close is traced as a cancellation")
    func constructionFinishingAfterCloseIsTracedAsCancellation() async throws {
        let probe = EagerAsyncProbe()
        let buffer = DIBoundedTraceBuffer(capacity: 16)
        let container = AsyncOnDemandContainer(
            probe: probe,
            _innoDITrace: DITraceContext(sink: buffer)
        )
        let waiting = Task { try await container.resource }
        await probe.waitForStarts(1)
        await container.closeAsyncProviders()
        await #expect(throws: Self.closed) { try await waiting.value }

        await probe.openGate()
        #expect(await probe.waitForCompletions(1) == [true])
        while buffer.snapshot().events.count < 2 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        #expect(buffer.snapshot().events.map(\.kind) == [.start, .cancel])
    }

    @Test("Tracing records an override at initialization")
    func tracingRecordsOverride() async throws {
        let buffer = DIBoundedTraceBuffer(capacity: 16)
        let container = AsyncOnDemandContainer(
            probe: EagerAsyncProbe(),
            resource: AsyncOnDemandResource(generation: 7),
            _innoDITrace: DITraceContext(sink: buffer)
        )
        #expect(buffer.snapshot().events.map(\.kind) == [.start, .override])

        _ = try await container.resource
        #expect(buffer.snapshot().events.map(\.kind) == [.start, .override, .cacheHit])
    }
}
