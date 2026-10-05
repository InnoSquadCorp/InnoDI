import Foundation
@testable import InnoDI
import Testing

private actor CancelTestSignal {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private enum CancelTestFailure: Error { case expected }

private actor CancelTestCounter {
    private var value = 0
    func increment() -> Int { value += 1; return value }
    func snapshot() -> Int { value }
}

private final class CancelTestToken: Sendable {
    let value = 42
}

private extension DIAsyncScope {
    func cancelTestWaiterCount() -> Int {
        let storage = Mirror(reflecting: self).children.first { $0.label == "waiters" }?.value
        return (storage as? [UUID: CheckedContinuation<Value, any Error>])?.count ?? -1
    }

    func cancelTestReservationWaiterCount() -> Int {
        let storage = Mirror(reflecting: self).children.first { $0.label == "reservationWaiters" }?.value
        return (storage as? [CheckedContinuation<Void, Never>])?.count ?? -1
    }
}

@Suite("Async scope retryable cancellation", .timeLimit(.minutes(1)))
struct DIAsyncScopeCancellationTests {
    @Test("Idle cancellation retains the factory and does not require retry")
    func idleCancellationIsNoOp() async throws {
        let counter = CancelTestCounter()
        var token: CancelTestToken? = CancelTestToken()
        weak var weakToken = token
        defer { weakToken = nil }
        let scope = DIAsyncScope<Int>(providerID: "idle") { [token = token!] in
            _ = await counter.increment()
            return token.value
        }
        token = nil
        await scope.cancel()
        await scope.cancel()
        #expect(await scope.status() == DIAsyncProviderStatus(providerID: "idle", generation: 0, state: .idle))
        #expect(await counter.snapshot() == 0)
        #expect(weakToken != nil)
        await #expect(throws: DIAsyncScopeError.retryRequiresFailure(providerID: "idle")) { try await scope.retry() }
        #expect(try await scope.value() == 42)
        #expect(await counter.snapshot() == 1)
        #expect(await scope.status().generation == 0)
        await scope.close()
        #expect(weakToken == nil)
    }

    @Test("Running cancellation resumes all waiters and cancels the owned task")
    func runningCancellationResumesWaiters() async throws {
        let started = CancelTestSignal()
        let release = CancelTestSignal()
        let ended = AsyncStream<Bool>.makeStream()
        let scope = DIAsyncScope(providerID: "running") {
            await started.open()
            await release.wait()
            ended.continuation.yield(Task.isCancelled)
            ended.continuation.finish()
            return 7
        }
        let waiters = (0..<40).map { _ in Task { try await scope.value() } }
        await started.wait()
        while await scope.cancelTestWaiterCount() != waiters.count { await Task.yield() }
        await scope.cancel()
        for waiter in waiters {
            await #expect(throws: CancellationError.self) { try await waiter.value }
        }
        #expect(await scope.cancelTestWaiterCount() == 0)
        #expect(await scope.status().state == .cancelled)
        #expect(await scope.status().generation == 0)
        await release.open()
        var completion = ended.stream.makeAsyncIterator()
        #expect(await completion.next() == true)
        // Late success from a cancellation-ignoring operation cannot become
        // the result of the explicitly cancelled generation.
        await #expect(throws: CancellationError.self) { try await scope.value() }
        try await scope.retry()
        #expect(await scope.status().state == .idle)
        #expect(await scope.status().generation == 1)
        #expect(try await scope.value() == 7)
        #expect(await scope.status().state == .ready)
        await scope.close()
    }

    @Test("Ready, failed, cancelled, and closed states are stable under cancellation",
          arguments: [DIAsyncProviderStatus.State.ready, .failed, .cancelled, .closed])
    func terminalCancellationIsNoOp(state: DIAsyncProviderStatus.State) async throws {
        let scope = DIAsyncScope<Int>(providerID: "stable") {
            if state == .failed { throw CancelTestFailure.expected }
            if state == .cancelled { throw CancellationError() }
            return 1
        }
        if state == .closed { await scope.close() }
        else { _ = await scope.prepare() }
        let original = await scope.status()
        await scope.cancel()
        #expect(await scope.status() == original)
        if state == .ready { #expect(try await scope.value() == 1) }
        await scope.close()
    }

    @Test("A reset ready override ignores cancellation and retains its identity")
    func idleSeedCancellationIsNoOp() async throws {
        let token = CancelTestToken()
        let scope = DIAsyncScope(value: token, providerID: "seed")
        await scope.cancel()
        #expect(await scope.status().state == .ready)
        try await scope.resetForSubgraphRetry()
        await scope.cancel()
        #expect(await scope.status().state == .idle)
        #expect(await scope.status().generation == 1)
        #expect(try await scope.start().state == .ready)
        #expect(try await scope.value() === token)
        #expect(await scope.status().generation == 1)
        await scope.close()
    }

    @Test("Cancellation waits for retry reservation rollback without changing its generation")
    func cancellationRespectsRetryReservation() async throws {
        let failed = DIAsyncScope<Int>(providerID: "failed") { throw CancelTestFailure.expected }
        let child = DIAsyncScope(providerID: "child") { 2 }
        _ = await failed.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: child, dependencies: ["failed"])
        ])
        let reserved = CancelTestSignal()
        let rollback = CancelTestSignal()
        let retry = Task {
            try await plan.retry(["child"], beforeCommit: {
                await reserved.open()
                await rollback.wait()
                throw CancelTestFailure.expected
            })
        }
        await reserved.wait()
        let cancelling = Task { await child.cancel() }
        while await child.cancelTestReservationWaiterCount() == 0 { await Task.yield() }
        await rollback.open()
        await #expect(throws: CancelTestFailure.expected) { try await retry.value }
        await cancelling.value
        #expect(await child.status() == DIAsyncProviderStatus(providerID: "child", generation: 0, state: .idle))
        #expect(await failed.status().generation == 0)
        #expect(try await child.value() == 2)
        #expect(await child.status().generation == 0)
        await child.close()
        await failed.close()
    }
}
