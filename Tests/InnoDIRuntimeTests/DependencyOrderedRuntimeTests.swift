import InnoDI
import Testing

@MainActor
final class DependencyOrderLog {
    var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

final class DependencyOrderValue: Sendable {
    let id: Int
    init(_ id: Int) { self.id = id }
}

@DIContainerRole(
    role: ContainerRole.local,
    mainActor: true,
    initializationOrder: ContainerInitializationOrder.dependency
)
fileprivate struct DependencyOrderedRuntimeContainer {
    @Input var log: DependencyOrderLog
    @Provide(.shared, factory: { (third: DependencyOrderValue, log: DependencyOrderLog) in
        log.record("first")
        return third
    }) var first: DependencyOrderValue
    @Provide(.shared, factory: { (log: DependencyOrderLog) in
        log.record("middle")
        return DependencyOrderValue(2)
    }) var middle: DependencyOrderValue
    @Provide(.shared, factory: { (log: DependencyOrderLog) in
        log.record("third")
        return DependencyOrderValue(3)
    }) var third: DependencyOrderValue
}

@DIContainerRole(
    role: ContainerRole.local,
    mainActor: true,
    initializationOrder: ContainerInitializationOrder.dependency
)
fileprivate struct AlreadyOrderedRuntimeContainer {
    @Input var log: DependencyOrderLog
    @Provide(.shared, factory: { (log: DependencyOrderLog) in
        log.record("a")
        return DependencyOrderValue(1)
    }) var a: DependencyOrderValue
    @Provide(.shared, factory: { (a: DependencyOrderValue, log: DependencyOrderLog) in
        log.record("b")
        return a
    }) var b: DependencyOrderValue
    @Provide(.shared, factory: { (log: DependencyOrderLog) in
        log.record("c")
        return DependencyOrderValue(3)
    }) var c: DependencyOrderValue
}

@DIContainerRole(
    role: ContainerRole.local,
    mainActor: true,
    initializationOrder: ContainerInitializationOrder.dependency
)
fileprivate struct DependencyOrderedLazyRuntimeContainer {
    @Input var log: DependencyOrderLog
    @Provide(.shared, initialization: .onDemand,
             factory: { (leaf: DependencyOrderValue, log: DependencyOrderLog) in
        log.record("consumer")
        return leaf
    }) var consumer: DependencyOrderValue
    @Provide(.shared, initialization: .onDemand,
             factory: { (log: DependencyOrderLog) in
        log.record("leaf")
        return DependencyOrderValue(1)
    }) var leaf: DependencyOrderValue
}

@DIContainer(initializationOrder: ContainerInitializationOrder.dependency)
fileprivate struct DependencyOrderedAsyncRuntimeContainer {
    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { (leaf: DependencyOrderValue) async throws in leaf })
    var consumer: DependencyOrderValue
    @Provide(.shared, initialization: .onDemand,
             asyncFactory: { () async in DependencyOrderValue(1) })
    var leaf: DependencyOrderValue
}

@Suite("Dependency-ordered construction")
struct DependencyOrderedRuntimeTests {
    @MainActor
    @Test("Forward construction follows dependency order with stable ready ties")
    func forwardOrderAndTrace() {
        let log = DependencyOrderLog()
        let trace = DIBoundedTraceBuffer(capacity: 64)
        let container = DependencyOrderedRuntimeContainer(log: log, _innoDITrace: .init(sink: trace))
        #expect(log.events == ["middle", "third", "first"])
        #expect(container.first === container.third)
        #expect(container.first === container.first)
        let names = trace.snapshot().events.filter { $0.kind == .start }.compactMap {
            $0.providerID.split(separator: ".").last.map(String.init)
        }.filter { ["first", "middle", "third"].contains($0) }
        #expect(names == ["middle", "third", "first"])
    }

    @MainActor
    @Test("Already valid declarations keep their observable order")
    func preservesExistingOrder() {
        let log = DependencyOrderLog()
        let container = AlreadyOrderedRuntimeContainer(log: log)
        #expect(log.events == ["a", "b", "c"])
        #expect(container.a === container.b)
    }

    @MainActor
    @Test("Override suppresses its own factory without pruning eager predecessors")
    func overrideSuppression() {
        let log = DependencyOrderLog()
        let replacement = DependencyOrderValue(99)
        let container = DependencyOrderedRuntimeContainer(log: log, first: replacement)
        #expect(log.events == ["middle", "third"])
        #expect(container.first === replacement)
        #expect(container.first !== container.third)
    }

    @MainActor
    @Test("Ordering lazy cell setup does not construct unused services")
    func preservesOnDemandAndCopyIdentity() {
        let log = DependencyOrderLog()
        let container = DependencyOrderedLazyRuntimeContainer(log: log)
        let copy = container
        #expect(log.events.isEmpty)
        let value = copy.consumer
        #expect(log.events == ["leaf", "consumer"])
        #expect(container.consumer === value)
        #expect(container.leaf === value)
        #expect(log.events == ["leaf", "consumer"])
    }

    @MainActor
    @Test("An overridden lazy consumer leaves its unused predecessor idle")
    func lazyOverrideKeepsPredecessorIdle() {
        let log = DependencyOrderLog()
        let replacement = DependencyOrderValue(99)
        let container = DependencyOrderedLazyRuntimeContainer(log: log, consumer: replacement)
        #expect(container.consumer === replacement)
        #expect(log.events.isEmpty)
    }

    @Test("Forward async cells preserve shared identity and explicit close")
    func asyncForwardIdentityAndClose() async throws {
        let container = DependencyOrderedAsyncRuntimeContainer()
        let consumer = try await container.consumer
        let leaf = try await container.leaf
        #expect(consumer === leaf)
        await container.closeAsyncProviders()
        await #expect(throws: DIAsyncScopeError.closed(providerID: "consumer")) {
            _ = try await container.consumer
        }
    }
}
