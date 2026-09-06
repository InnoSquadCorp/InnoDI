import Foundation
import Testing

@testable import InnoDI

private final class GeneratedTraceValue: @unchecked Sendable {
    let sequence: Int

    init(sequence: Int) {
        self.sequence = sequence
    }
}

private final class GeneratedTraceCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func make() -> GeneratedTraceValue {
        lock.lock()
        count += 1
        let sequence = count
        lock.unlock()
        return GeneratedTraceValue(sequence: sequence)
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private enum GeneratedTraceFailure: Error {
    case failed
}

@DIContainer
fileprivate struct GeneratedTraceContainer {
    @Input var counter: GeneratedTraceCounter

    @Provide(.shared, factory: { (counter: GeneratedTraceCounter) in
        counter.make()
    })
    var eager: GeneratedTraceValue

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (counter: GeneratedTraceCounter) in counter.make() }
    )
    var onDemand: GeneratedTraceValue

    @Provide(.transient, factory: { (counter: GeneratedTraceCounter) in
        counter.make()
    })
    var transient: GeneratedTraceValue

    @Provide(.shared, asyncFactory: { (eager: GeneratedTraceValue) async in
        await Task.yield()
        return eager
    })
    var asyncShared: GeneratedTraceValue

    @Provide(
        .shared,
        asyncFactory: { (asyncShared: GeneratedTraceValue) async in
            asyncShared
        }
    )
    var asyncDownstream: GeneratedTraceValue

    @Provide(
        .transient,
        asyncFactory: { (counter: GeneratedTraceCounter) async throws in
            _ = counter.snapshot()
            throw GeneratedTraceFailure.failed
        }
    )
    var failing: GeneratedTraceValue

    @Provide(
        .transient,
        asyncFactory: { (counter: GeneratedTraceCounter) async throws in
            _ = counter.snapshot()
            throw CancellationError()
        }
    )
    var cancelling: GeneratedTraceValue
}

@Suite("DI runtime tracing")
struct DITracingTests {
    private enum ExpectedFailure: Error { case failed }

    @Test("disabled tracing does not evaluate or allocate events")
    func disabledPathIsLazy() {
        var evaluations = 0
        let context = DITraceContext.disabled
        context.emit({
            evaluations += 1
            return DITraceEvent(
                providerID: "App.secret",
                instanceID: UUID(),
                kind: .start
            )
        }())

        #expect(!context.isEnabled)
        #expect(evaluations == 0)
        #expect(context.start(providerID: "App.secret") == nil)
    }

    @Test("bounded buffers retain newest metadata-only events")
    func boundedBuffer() throws {
        let buffer = DIBoundedTraceBuffer(capacity: 2)
        let context = DITraceContext(sink: buffer, generation: 9)
        let first = try #require(context.start(providerID: "App.first"))
        context.record(.success, providerID: "App.first", instanceID: first)
        _ = try #require(context.start(providerID: "App.second"))

        let snapshot = buffer.snapshot()
        #expect(snapshot.events.map(\.providerID) == ["App.first", "App.second"])
        #expect(snapshot.events.map(\.kind) == [.success, .start])
        #expect(snapshot.events.allSatisfy { $0.generation == 9 })
        #expect(snapshot.events.map(\.origin) == [.factory, .factory])
        #expect(snapshot.droppedEventCount == 1)
    }

    @Test("concurrent writers do not lose events below capacity")
    func concurrentWriters() async {
        let buffer = DIBoundedTraceBuffer(capacity: 200)
        let context = DITraceContext(sink: buffer)

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<100 {
                group.addTask {
                    let providerID = "App.provider\(index)"
                    let instanceID = context.start(providerID: providerID)
                    context.record(.success, providerID: providerID, instanceID: instanceID)
                }
            }
        }

        let snapshot = buffer.snapshot()
        #expect(snapshot.events.count == 200)
        #expect(snapshot.droppedEventCount == 0)
        #expect(Set(snapshot.events.map(\.instanceID)).count == 100)
    }

    @Test("resolution spans report every terminal outcome without payloads")
    func resolutionOutcomesAreMetadataOnly() async throws {
        let secretCanary = "token-super-secret-42"
        let buffer = DIBoundedTraceBuffer(capacity: 16)
        let context = DITraceContext(sink: buffer)

        let value = context.withResolution(providerID: "App.success") { 42 }
        #expect(value == 42)
        #expect(throws: ExpectedFailure.failed) {
            try context.withResolution(providerID: "App.failure") {
                _ = secretCanary
                throw ExpectedFailure.failed
            }
        }
        await #expect(throws: CancellationError.self) {
            try await context.withResolution(providerID: "App.cancel") {
                await Task.yield()
                throw CancellationError()
            }
        }

        let events = buffer.snapshot().events
        #expect(events.map(\.kind) == [
            .start, .success, .start, .failure, .start, .cancel,
        ])
        #expect(Set(events.map(\.instanceID)).count == 3)
        let encoded = try String(
            decoding: JSONEncoder().encode(events),
            as: UTF8.self
        )
        #expect(!encoded.contains(secretCanary))
    }

    @Test("disabled resolution spans execute directly")
    func disabledResolutionExecutesDirectly() async throws {
        let context = DITraceContext.disabled
        var syncCalls = 0
        let syncValue = context.withResolution(providerID: "App.sync") {
            syncCalls += 1
            return 1
        }
        let asyncValue = await context.withResolution(providerID: "App.async") {
            await Task.yield()
            return 2
        }

        #expect(syncValue == 1)
        #expect(asyncValue == 2)
        #expect(syncCalls == 1)
    }

    @Test("generated providers automatically correlate factory, cache, override, and terminal events")
    func generatedProvidersAreAutomaticallyTraced() async throws {
        let buffer = DIBoundedTraceBuffer(capacity: 128)
        let context = DITraceContext(
            sink: buffer,
            targetIDsByModule: [
                "InnoDIRuntimeTests": "swiftpm:innodi:InnoDIRuntimeTests"
            ],
            generation: 7
        )
        let counter = GeneratedTraceCounter()
        let replacement = GeneratedTraceValue(sequence: 999)
        let container = GeneratedTraceContainer(
            counter: counter,
            _innoDITrace: context
        ) { overrides in
            overrides.transient = replacement
        }

        let eager = container.eager
        let onDemandFirst = container.onDemand
        let onDemandSecond = container.onDemand
        let transient = container.transient
        let asyncShared = await container.asyncShared
        let asyncDownstream = await container.asyncDownstream
        await #expect(throws: GeneratedTraceFailure.failed) {
            try await container.failing
        }
        await #expect(throws: CancellationError.self) {
            try await container.cancelling
        }

        #expect(eager.sequence == 1)
        #expect(onDemandFirst === onDemandSecond)
        #expect(transient === replacement)
        #expect(asyncShared === eager)
        #expect(asyncDownstream === asyncShared)
        #expect(counter.snapshot() == 2)

        let events = buffer.snapshot().events
        let prefix = "swiftpm:innodi:InnoDIRuntimeTests::GeneratedTraceContainer."
        #expect(events.allSatisfy { $0.providerID.hasPrefix(prefix) })
        #expect(events.allSatisfy { $0.generation == 7 })
        #expect(Set(events.map(\.ownerID)).count == 1)

        func kinds(_ member: String) -> [DITraceEvent.Kind] {
            events
                .filter { $0.providerID == prefix + member }
                .map(\.kind)
        }

        #expect(kinds("eager").starts(with: [.start, .success]))
        #expect(kinds("eager").contains(.cacheHit))
        #expect(kinds("onDemand") == [.start, .success, .cacheHit])
        #expect(kinds("transient") == [.start, .override])
        #expect(kinds("asyncShared").starts(with: [.start, .success]))
        #expect(kinds("asyncShared").contains(.cacheHit))
        #expect(kinds("asyncDownstream").contains(.waitStart))
        #expect(kinds("asyncDownstream").contains(.waitEnd))
        #expect(kinds("asyncDownstream").contains(.success))
        #expect(kinds("failing") == [.start, .failure])
        #expect(kinds("cancelling") == [.start, .cancel])
        #expect(
            events.first { $0.providerID == prefix + "transient" && $0.kind == .override }?.origin
                == .containerOverride
        )
        let asyncWait = try #require(
            events.first {
                $0.providerID == prefix + "asyncDownstream"
                    && $0.kind == .waitStart
            }
        )
        #expect(asyncWait.relatedProviderID == prefix + "asyncShared")
        #expect(asyncWait.relatedInstanceID != nil)
    }

    @Test("on-demand cells expose real waiter relationships without payloads")
    func onDemandWaitRelationships() async throws {
        let buffer = DIBoundedTraceBuffer(capacity: 32)
        let context = DITraceContext(
            sink: buffer,
            targetIDsByModule: ["InnoDIRuntimeTests": "swiftpm:innodi:InnoDIRuntimeTests"],
            generation: 11
        )
        let owner = _InnoDITraceOwner(
            context: context,
            containerType: GeneratedTraceContainer.self
        )
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let cell = _InnoDISharedCell<GeneratedTraceValue>(
            traceOwner: owner,
            providerName: "slow"
        ) {
            entered.signal()
            release.wait()
            return GeneratedTraceValue(sequence: 1)
        }

        let first = Task.detached { cell.value() }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                entered.wait()
                continuation.resume()
            }
        }
        let second = Task.detached { cell.value() }
        try await Task.sleep(for: .milliseconds(20))
        release.signal()
        let values = await [first.value, second.value]
        #expect(values[0] === values[1])

        let events = buffer.snapshot().events
        #expect(events.map(\.kind).contains(.waitStart))
        #expect(events.map(\.kind).contains(.waitEnd))
        let waits = events.filter { $0.kind == .waitStart || $0.kind == .waitEnd }
        #expect(waits.allSatisfy { $0.origin == .wait })
        #expect(waits.allSatisfy { $0.relatedProviderID == $0.providerID })
        #expect(waits.allSatisfy { $0.relatedInstanceID == $0.instanceID })
        #expect(waits.allSatisfy { $0.generation == 11 })
    }

    @Test("separate generated owners and generations never share runtime identity")
    func ownersAndGenerationsRemainDistinct() {
        let buffer = DIBoundedTraceBuffer(capacity: 32)
        let first = GeneratedTraceContainer(
            counter: GeneratedTraceCounter(),
            _innoDITrace: DITraceContext(sink: buffer, generation: 21)
        )
        let second = GeneratedTraceContainer(
            counter: GeneratedTraceCounter(),
            _innoDITrace: DITraceContext(sink: buffer, generation: 22)
        )

        _ = first.transient
        _ = second.transient

        let events = buffer.snapshot().events
        #expect(Set(events.map(\.generation)) == [21, 22])
        let ownersByGeneration = Dictionary(grouping: events, by: \.generation)
            .mapValues { Set($0.map(\.ownerID)) }
        #expect(ownersByGeneration[21]?.count == 1)
        #expect(ownersByGeneration[22]?.count == 1)
        #expect(ownersByGeneration[21] != ownersByGeneration[22])
    }
}
