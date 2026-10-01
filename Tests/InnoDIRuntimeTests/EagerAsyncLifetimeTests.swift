import InnoDI
import Testing

// Pins the documented lifetime of an eager `.shared` provider built by
// `asyncFactory:`. The generated initializer starts an unstructured task
// before any read, the container never cancels it, and a `.transient`
// sub-container starts its child's eager asynchronous work on every read.

actor EagerAsyncProbe {
    private var starts = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var gateOpen = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var completions: [Bool] = []
    private var completionWaiters: [(count: Int, continuation: CheckedContinuation<[Bool], Never>)] = []

    func recordStart() {
        starts += 1
        let ready = startWaiters.filter { $0.count <= starts }
        startWaiters.removeAll { $0.count <= starts }
        for waiter in ready { waiter.continuation.resume() }
    }

    func waitForStarts(_ count: Int) async {
        guard starts < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func startCount() -> Int { starts }

    func waitForGate() async {
        guard !gateOpen else { return }
        await withCheckedContinuation { gateWaiters.append($0) }
    }

    func openGate() {
        gateOpen = true
        let waiters = gateWaiters
        gateWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func recordCompletion(cancelled: Bool) {
        completions.append(cancelled)
        let ready = completionWaiters.filter { $0.count <= completions.count }
        completionWaiters.removeAll { $0.count <= completions.count }
        for waiter in ready { waiter.continuation.resume(returning: completions) }
    }

    func waitForCompletions(_ count: Int) async -> [Bool] {
        guard completions.count < count else { return completions }
        return await withCheckedContinuation { completionWaiters.append((count, $0)) }
    }
}

struct EagerAsyncResource: Equatable, Sendable {
    let generation: Int
}

@DIContainer
struct EagerAsyncLifetimeContainer {
    @Input var probe: EagerAsyncProbe

    @Provide(.shared, asyncFactory: { (probe: EagerAsyncProbe) async in
        await probe.recordStart()
        await probe.waitForGate()
        await probe.recordCompletion(cancelled: Task.isCancelled)
        return EagerAsyncResource(generation: 1)
    })
    var resource: EagerAsyncResource
}

@DIContainer
struct EagerAsyncLifetimeParent {
    @Input var probe: EagerAsyncProbe

    @SubContainer(scope: .transient)
    var child: EagerAsyncLifetimeContainer
}

@Suite("Eager async shared provider lifetime", .timeLimit(.minutes(1)))
struct EagerAsyncLifetimeTests {
    @Test("An eager async shared provider starts during initialization without a read")
    func startsDuringInitialization() async {
        let probe = EagerAsyncProbe()
        let container = EagerAsyncLifetimeContainer(probe: probe)

        await probe.waitForStarts(1)
        #expect(await probe.startCount() == 1)

        await probe.openGate()
        #expect(await container.resource == EagerAsyncResource(generation: 1))
    }

    @Test("Releasing the container does not cancel eager async construction")
    func releasingContainerDoesNotCancel() async {
        let probe = EagerAsyncProbe()
        do {
            _ = EagerAsyncLifetimeContainer(probe: probe)
        }

        await probe.waitForStarts(1)
        await probe.openGate()
        #expect(await probe.waitForCompletions(1) == [false])
    }

    @Test("Cancelling a reader does not cancel eager async construction")
    func cancellingReaderDoesNotCancel() async {
        let probe = EagerAsyncProbe()
        let container = EagerAsyncLifetimeContainer(probe: probe)
        let reader = Task { await container.resource }

        await probe.waitForStarts(1)
        reader.cancel()
        await probe.openGate()

        #expect(await probe.waitForCompletions(1) == [false])
        #expect(await reader.value == EagerAsyncResource(generation: 1))
    }

    @Test("Each transient sub-container read starts the child's eager async work again")
    func transientSubContainerReadsRestartWork() async {
        let probe = EagerAsyncProbe()
        let parent = EagerAsyncLifetimeParent(probe: probe)

        _ = parent.child
        _ = parent.child

        await probe.waitForStarts(2)
        #expect(await probe.startCount() == 2)

        await probe.openGate()
        #expect(await probe.waitForCompletions(2) == [false, false])
    }
}
