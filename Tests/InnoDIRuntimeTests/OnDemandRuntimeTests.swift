import Foundation
import InnoDI
import Testing

final class OnDemandCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func make() -> OnDemandService {
        lock.lock()
        count += 1
        let identifier = count
        lock.unlock()
        return OnDemandService(identifier: identifier)
    }

    func snapshot() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

final class OnDemandService: @unchecked Sendable {
    let identifier: Int
    init(identifier: Int) { self.identifier = identifier }
}

final class OnDemandLazyConsumer {
    let service: InnoDI.Lazy<OnDemandService>
    init(service: InnoDI.Lazy<OnDemandService>) { self.service = service }
}

final class OnDemandProviderConsumer {
    let service: InnoDI.Provider<OnDemandService>
    init(service: InnoDI.Provider<OnDemandService>) { self.service = service }
}

private final class LockedServiceCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [OnDemandService] = []

    func append(_ value: OnDemandService) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [OnDemandService] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class TestSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private final class OnDemandLifetimeInput {}

@DIContainer
fileprivate struct OnDemandLifetimeContainer {
    @Input var input: OnDemandLifetimeInput

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (input: OnDemandLifetimeInput) in input }
    )
    var value: OnDemandLifetimeInput
}

@DIContainer
struct OnDemandContainer {
    @Input var counter: OnDemandCounter

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (counter: OnDemandCounter) in counter.make() }
    )
    var service: OnDemandService

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (counter: OnDemandCounter) in counter.make() }
    )
    var secondary: OnDemandService
}

@DIContainer
struct OnDemandWrapperContainer {
    @Input var counter: OnDemandCounter

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (counter: OnDemandCounter) in counter.make() }
    )
    var service: OnDemandService

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (service: InnoDI.Lazy<OnDemandService>) in
            OnDemandLazyConsumer(service: service)
        }
    )
    var lazyConsumer: OnDemandLazyConsumer

    @Provide(
        .transient,
        factory: { (counter: OnDemandCounter) in counter.make() }
    )
    var transientService: OnDemandService

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (transientService: InnoDI.Provider<OnDemandService>) in
            OnDemandProviderConsumer(service: transientService)
        }
    )
    var providerConsumer: OnDemandProviderConsumer
}

@DIContainer
struct OnDemandFixedChildContainer {
    @Input var service: OnDemandService
}

@DIContainer
struct OnDemandFixedParentContainer {
    @Input var counter: OnDemandCounter

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (counter: OnDemandCounter) in counter.make() }
    )
    var service: OnDemandService

    @SubContainer(
        scope: .shared,
        with: [\OnDemandFixedParentContainer.service]
    )
    var child: OnDemandFixedChildContainer
}

@DIContainer
struct OnDemandAsyncOverrideContainer {
    @Input var counter: OnDemandCounter

    @Provide(
        .shared,
        initialization: .onDemand,
        factory: { (counter: OnDemandCounter) in counter.make() }
    )
    var service: OnDemandService

    @Provide(
        .shared,
        asyncFactory: { (service: OnDemandService) async in
            service.identifier
        }
    )
    var primary: Int

    @Provide(
        .shared,
        asyncFactory: { (service: OnDemandService) async in
            service.identifier * 10
        }
    )
    var secondary: Int
}

@Suite("On-demand shared providers")
struct OnDemandRuntimeTests {
    @Test("An unresolved on-demand provider releases its captured input with the container")
    func unresolvedOnDemandProviderReleasesLastOwner() {
        weak var weakInput: OnDemandLifetimeInput?

        do {
            let input = OnDemandLifetimeInput()
            weakInput = input
            _ = OnDemandLifetimeContainer(input: input)
        }

        #expect(weakInput == nil)
    }

    @Test("construction waits for first access and container copies share identity")
    func lazyConstructionAndCopySemantics() {
        let counter = OnDemandCounter()
        let original = OnDemandContainer(counter: counter)
        let copy = original
        #expect(counter.snapshot() == 0)

        let first = original.service
        let second = copy.service
        #expect(first === second)
        #expect(counter.snapshot() == 1)

        let independent = OnDemandContainer(counter: counter)
        let third = independent.service
        #expect(third !== first)
        #expect(counter.snapshot() == 2)
    }

    @Test("an override bypasses the original factory")
    func overridePrecedence() {
        let counter = OnDemandCounter()
        let replacement = OnDemandService(identifier: 99)
        let container = OnDemandContainer(
            counter: counter,
            service: replacement
        )

        #expect(container.service === replacement)
        #expect(counter.snapshot() == 0)
    }

    @Test("prewarming resolves only selected on-demand providers")
    func selectivePrewarming() throws {
        let counter = OnDemandCounter()
        let container = OnDemandContainer(counter: counter)

        try container.prewarm(\OnDemandContainer.service)
        #expect(counter.snapshot() == 1)
        _ = container.service
        #expect(counter.snapshot() == 1)
        _ = container.secondary
        #expect(counter.snapshot() == 2)

        #expect(throws: DIPrewarmError.unsupportedProvider) {
            try container.prewarm(\OnDemandContainer.counter)
        }
    }

    @Test("the runtime cell coalesces concurrent readers")
    func concurrentReadersShareOneConstruction() {
        let counter = OnDemandCounter()
        let cell = _InnoDISharedCell<OnDemandService>(
            factory: { counter.make() }
        )
        let cellBox = TestSendableBox(cell)
        let collector = LockedServiceCollector()

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            collector.append(cellBox.value.value())
        }

        let values = collector.snapshot()
        #expect(counter.snapshot() == 1)
        #expect(values.count == 100)
        #expect(values.allSatisfy { $0 === values[0] })
    }

    @Test("prewarming wrapper consumers does not evaluate lazy or provider targets")
    func prewarmPreservesWrapperDeferral() throws {
        let counter = OnDemandCounter()
        let container = OnDemandWrapperContainer(counter: counter)

        try container.prewarm(\OnDemandWrapperContainer.lazyConsumer)
        #expect(counter.snapshot() == 0)
        let lazyFirst = container.lazyConsumer.service()
        let lazySecond = container.lazyConsumer.service()
        #expect(lazyFirst === lazySecond)
        #expect(counter.snapshot() == 1)

        try container.prewarm(\OnDemandWrapperContainer.providerConsumer)
        #expect(counter.snapshot() == 1)
        let transientFirst = container.providerConsumer.service()
        let transientSecond = container.providerConsumer.service()
        #expect(transientFirst !== transientSecond)
        #expect(counter.snapshot() == 3)
    }

    @Test("a fixed shared child resolves an on-demand parent input exactly once")
    func fixedChildUsesOnDemandInput() throws {
        let counter = OnDemandCounter()
        let parent = OnDemandFixedParentContainer(counter: counter)
        #expect(counter.snapshot() == 1)
        #expect(parent.child.service === parent.service)

        try parent.prewarm(\OnDemandFixedParentContainer.service)
        #expect(counter.snapshot() == 1)
    }

    @Test("async overrides evaluate only dependencies used by live factories")
    func asyncOverridesPreserveOnDemandDeferral() async {
        let allOverrideCounter = OnDemandCounter()
        let allOverridden = OnDemandAsyncOverrideContainer(
            counter: allOverrideCounter,
            primary: 7,
            secondary: 8
        )
        #expect(await allOverridden.primary == 7)
        #expect(await allOverridden.secondary == 8)
        #expect(allOverrideCounter.snapshot() == 0)

        let partialCounter = OnDemandCounter()
        let partiallyOverridden = OnDemandAsyncOverrideContainer(
            counter: partialCounter,
            primary: 9
        )
        #expect(await partiallyOverridden.primary == 9)
        #expect(await partiallyOverridden.secondary == 10)
        // The live secondary task is the sole consumer of the shared
        // on-demand dependency, regardless of task scheduling order.
        #expect(partialCounter.snapshot() == 1)

        let liveCounter = OnDemandCounter()
        let live = OnDemandAsyncOverrideContainer(counter: liveCounter)
        #expect(await live.primary == 1)
        #expect(await live.secondary == 10)
        #expect(liveCounter.snapshot() == 1)
    }
}
