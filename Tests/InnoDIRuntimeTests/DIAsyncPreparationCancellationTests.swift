import Foundation
@testable import InnoDI
import Testing

private actor PreparationGate {
    private var entered = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var result: CheckedContinuation<Int, Never>?
    private(set) var calls = 0

    func run() async -> Int {
        calls += 1
        entered = true
        let pending = entryWaiters
        entryWaiters.removeAll()
        for waiter in pending { waiter.resume() }
        return await withCheckedContinuation { result = $0 }
    }

    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiters.append($0) }
    }

    func finish() {
        result?.resume(returning: 42)
        result = nil
    }
}

private actor CancellingPreparationProvider: DIAsyncPreparing {
    nonisolated let providerID = "custom"
    private var state: DIAsyncProviderStatus.State = .idle

    func status() -> DIAsyncProviderStatus {
        .init(providerID: providerID, generation: 0, state: state)
    }

    func prepare() -> DIAsyncProviderStatus {
        state = .ready
        withUnsafeCurrentTask { $0?.cancel() }
        return status()
    }

    func retry() {}
    func close() { state = .closed }
}

@Suite("Preparation caller and provider cancellation", .timeLimit(.minutes(1)))
struct DIAsyncPreparationCancellationTests {
    @Test("Cancelling a preparation waiter reports the real running generation")
    func cancelledWaitKeepsProviderRunning() async throws {
        let gate = PreparationGate()
        let scope = DIAsyncScope(providerID: "service") { await gate.run() }
        let preparation = Task { await scope.prepare() }
        await gate.waitForEntry()
        preparation.cancel()
        let reported = await preparation.value
        let actual = await scope.status()
        #expect(reported.state == .running)
        #expect(reported == actual)
        await #expect(throws: DIAsyncScopeError.retryRequiresFailure(providerID: "service")) {
            try await scope.retry()
        }
        await gate.finish()
        #expect(try await scope.value() == 42)
        #expect(await gate.calls == 1)
        #expect(await scope.status().generation == 0)
        await scope.close()
    }

    @Test("An already cancelled scope preparation does not invent provider cancellation")
    func preCancelledScopeReportsActualState() async {
        let idle = DIAsyncScope(providerID: "idle") { 7 }
        let ready = DIAsyncScope(value: 9, providerID: "ready")
        let preparation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return (await idle.prepare(), await ready.prepare())
        }
        let (idleStatus, readyStatus) = await preparation.value
        #expect(idleStatus.state == .idle)
        #expect(readyStatus.state == .ready)
        await idle.close()
        await ready.close()
    }

    @Test("A cancelled plan caller throws and leaves provider work available without retry")
    func cancelledPlanWaitThrows() async throws {
        let gate = PreparationGate()
        let scope = DIAsyncScope(providerID: "service") { await gate.run() }
        let plan = try DIAsyncPreparationPlan(nodes: [.init(provider: scope)])
        let preparation = Task { try await plan.prepare(["service"]) }
        await gate.waitForEntry()
        preparation.cancel()
        await #expect(throws: CancellationError.self) { try await preparation.value }
        #expect(await scope.status().state == .running)
        await gate.finish()
        let report = try await plan.prepare(["service"])
        #expect(report.isReady)
        #expect(await gate.calls == 1)
        #expect(report.entries.first?.status.generation == 0)
        await scope.close()
    }

    @Test("Provider cancellation remains a reportable and retryable provider outcome")
    func providerCancellationRemainsDistinct() async throws {
        let gate = PreparationGate()
        let scope = DIAsyncScope(providerID: "service") { await gate.run() }
        let plan = try DIAsyncPreparationPlan(nodes: [.init(provider: scope)])
        let preparation = Task { try await plan.prepare(["service"]) }
        await gate.waitForEntry()
        await scope.cancel()
        let report = try await preparation.value
        #expect(report.entries.first?.disposition == .cancelled)
        #expect(report.entries.first?.status.state == .cancelled)
        await gate.finish()
        try await scope.retry()
        #expect(await scope.status().state == .idle)
        #expect(await scope.status().generation == 1)
        await scope.close()
    }

    @Test("A custom provider cannot turn caller cancellation into a ready plan")
    func customProviderCancellationStopsPlan() async throws {
        let provider = CancellingPreparationProvider()
        let downstream = DIAsyncScope(providerID: "downstream") { 7 }
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: provider),
            .init(provider: downstream, dependencies: ["custom"])
        ])
        let preparation = Task { try await plan.prepare(["downstream"]) }
        await #expect(throws: CancellationError.self) { try await preparation.value }
        #expect(await provider.status().state == .ready)
        #expect(await downstream.status().state == .idle)
        await downstream.close()
    }
}
