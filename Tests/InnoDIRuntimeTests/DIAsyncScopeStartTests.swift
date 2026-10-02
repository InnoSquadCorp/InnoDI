import Foundation
@testable import InnoDI
import Testing

private actor StartTestSignal {
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

private actor StartTestOperation {
    let started = StartTestSignal()
    let release = StartTestSignal()
    private var invocations = 0

    func run() async throws -> Int {
        invocations += 1
        await started.open()
        await release.wait()
        try Task.checkCancellation()
        return invocations
    }

    func count() -> Int { invocations }
}

private enum StartTestFailure: Error { case expected, rollback }

private actor StartRetryOperation {
    private var invocations = 0

    func run(cancelFirst: Bool) throws -> Int {
        invocations += 1
        if invocations == 1 {
            if cancelFirst { throw CancellationError() }
            throw StartTestFailure.expected
        }
        return invocations
    }

    func count() -> Int { invocations }
}

private extension DIAsyncScope {
    func startTestWaiterCount() -> Int {
        let storage = Mirror(reflecting: self).children.first { $0.label == "waiters" }?.value
        return (storage as? [UUID: CheckedContinuation<Value, any Error>])?.count ?? -1
    }

    func startTestReservationWaiterCount() -> Int {
        let storage = Mirror(reflecting: self).children.first { $0.label == "reservationWaiters" }?.value
        return (storage as? [CheckedContinuation<Void, Never>])?.count ?? -1
    }
}

@Suite("Async scope non-waiting start", .timeLimit(.minutes(1)))
struct DIAsyncScopeStartTests {
    @Test("Start admits before readiness and completion needs no waiter")
    func admissionDoesNotWaitForValue() async throws {
        let operation = StartTestOperation()
        let scope = DIAsyncScope(providerID: "start") { try await operation.run() }

        let admitted = try await scope.start()
        #expect(admitted == DIAsyncProviderStatus(providerID: "start", generation: 0, state: .running))
        await operation.started.wait()
        #expect(await scope.startTestWaiterCount() == 0)
        #expect(await operation.count() == 1)

        await operation.release.open()
        // Observe the scope's completion without registering a value waiter.
        while await scope.status().state == .running { await Task.yield() }
        #expect(await scope.status().state == .ready)
        #expect(await scope.startTestWaiterCount() == 0)
        #expect(try await scope.value() == 1)
        #expect(try await scope.start().state == .ready)
        await scope.close()
    }

    @Test("Concurrent starts coalesce with ordinary value waiters")
    func concurrentStartsShareOwnedTask() async throws {
        let operation = StartTestOperation()
        let scope = DIAsyncScope(providerID: "shared") { try await operation.run() }
        let starts = (0..<40).map { _ in Task { try await scope.start() } }
        let values = (0..<40).map { _ in Task { try await scope.value() } }
        for start in starts {
            #expect(try await start.value.state == .running)
        }
        await operation.started.wait()
        #expect(await operation.count() == 1)
        await operation.release.open()
        for value in values { #expect(try await value.value == 1) }
        #expect(await scope.status().generation == 0)
        await scope.close()
    }

    @Test("A pre-cancelled start cannot admit work")
    func preCancelledStartDoesNotRun() async throws {
        let operation = StartTestOperation()
        let scope = DIAsyncScope(providerID: "cancelled-start") { try await operation.run() }
        let proceed = StartTestSignal()
        let caller = Task {
            await proceed.wait()
            return try await scope.start()
        }
        caller.cancel()
        await proceed.open()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await scope.status().state == .idle)
        #expect(await scope.startTestWaiterCount() == 0)
        #expect(await operation.count() == 0)
        await scope.close()
    }

    @Test("Cancelling the admission caller does not cancel already-owned work")
    func cancellationAfterAdmissionIsIsolated() async throws {
        let operation = StartTestOperation()
        let scope = DIAsyncScope(providerID: "owned") { try await operation.run() }
        let admitted = StartTestSignal()
        let returnToCaller = StartTestSignal()
        let caller = Task {
            let status = try await scope.start()
            await admitted.open()
            await returnToCaller.wait()
            return status
        }
        await admitted.wait()
        await operation.started.wait()
        caller.cancel()
        await returnToCaller.open()
        #expect(try await caller.value.state == .running)
        #expect(await scope.startTestWaiterCount() == 0)
        await operation.release.open()
        #expect(try await scope.value() == 1)
        #expect(await scope.status().state == .ready)
        await scope.close()
    }

    @Test("Start preserves cached failure or cancellation until explicit retry", arguments: [false, true])
    func terminalAttemptIsCached(cancelFirst: Bool) async throws {
        let operation = StartRetryOperation()
        let scope = DIAsyncScope(providerID: "retry") { try await operation.run(cancelFirst: cancelFirst) }
        _ = await scope.prepare()
        let cached = await scope.status()
        #expect(cached.state == (cancelFirst ? .cancelled : .failed))
        for _ in 0..<10 { #expect(try await scope.start() == cached) }
        #expect(await operation.count() == 1)
        try await scope.retry()
        let admitted = try await scope.start()
        #expect(admitted.generation == 1)
        #expect(admitted.state == .running)
        #expect(try await scope.value() == 2)
        #expect(await operation.count() == 2)
        await scope.close()
    }

    @Test("Close before start is terminal and does not invoke the factory")
    func closedScopeRejectsStart() async throws {
        let operation = StartTestOperation()
        let scope = DIAsyncScope(providerID: "closed") { try await operation.run() }
        await scope.close()
        for _ in 0..<3 {
            await #expect(throws: DIAsyncScopeError.closed(providerID: "closed")) {
                try await scope.start()
            }
        }
        #expect(await operation.count() == 0)
        #expect(await scope.status().generation == 0)
    }

    @Test("Close cancels a task admitted without any value waiter")
    func closeCancelsWaiterFreeTask() async throws {
        let started = StartTestSignal()
        let release = StartTestSignal()
        let completed = AsyncStream<Bool>.makeStream()
        let scope = DIAsyncScope(providerID: "waiter-free-close") {
            await started.open()
            await release.wait()
            completed.continuation.yield(Task.isCancelled)
            completed.continuation.finish()
            return 7
        }
        #expect(try await scope.start().state == .running)
        await started.wait()
        #expect(await scope.startTestWaiterCount() == 0)
        await scope.close()
        await release.open()
        var completion = completed.stream.makeAsyncIterator()
        #expect(await completion.next() == true)
        #expect(await scope.status().state == .closed)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "waiter-free-close")) {
            try await scope.start()
        }
    }

    @Test("Concurrent close and start always leave terminal ownership", arguments: 0..<20)
    func startCloseRace(_ iteration: Int) async throws {
        let go = StartTestSignal()
        let operation = StartTestOperation()
        let scope = DIAsyncScope(providerID: "race") { try await operation.run() }
        let starting = Task { await go.wait(); return try await scope.start() }
        let closing = Task { await go.wait(); await scope.close() }
        await go.open()
        do {
            #expect(try await starting.value.state == .running)
        } catch {
            #expect(error as? DIAsyncScopeError == .closed(providerID: "race"))
        }
        await closing.value
        await operation.release.open()
        #expect(await scope.status().state == .closed)
        #expect(await scope.status().generation == 0)
        #expect(await operation.count() <= 1)
        await #expect(throws: DIAsyncScopeError.closed(providerID: "race")) {
            try await scope.start()
        }
    }

    @Test("Start waits for a retry commit and joins the committed generation")
    func startDuringReservedRetry() async throws {
        let operation = StartRetryOperation()
        let failed = DIAsyncScope(providerID: "failed") { try await operation.run(cancelFirst: false) }
        let childOperation = StartTestOperation()
        let child = DIAsyncScope(providerID: "child") { try await childOperation.run() }
        _ = await failed.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: child, dependencies: ["failed"])
        ])
        let reserved = StartTestSignal()
        let commit = StartTestSignal()
        let retry = Task {
            try await plan.retry(["child"], beforeCommit: {
                await reserved.open()
                await commit.wait()
            })
        }
        await reserved.wait()
        let starting = Task { try await child.start() }
        while await child.startTestReservationWaiterCount() == 0 { await Task.yield() }
        #expect(await childOperation.count() == 0)
        await commit.open()
        let admitted = try await starting.value
        #expect(admitted.state == .running)
        #expect(admitted.generation == 1)
        await childOperation.started.wait()
        await childOperation.release.open()
        #expect(try await retry.value.isReady)
        #expect(await childOperation.count() == 1)
        await child.close()
        await failed.close()
    }

    @Test("Cancellation while reserved prevents admission after rollback")
    func cancelledStartDuringReservedRetry() async throws {
        let failed = DIAsyncScope<Int>(providerID: "failed") { throw StartTestFailure.expected }
        let operation = StartTestOperation()
        let child = DIAsyncScope(providerID: "child") { try await operation.run() }
        _ = await failed.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: child, dependencies: ["failed"])
        ])
        let reserved = StartTestSignal()
        let rollback = StartTestSignal()
        let retry = Task {
            try await plan.retry(["child"], beforeCommit: {
                await reserved.open()
                await rollback.wait()
                throw StartTestFailure.rollback
            })
        }
        await reserved.wait()
        let starting = Task { try await child.start() }
        while await child.startTestReservationWaiterCount() == 0 { await Task.yield() }
        starting.cancel()
        await rollback.open()
        await #expect(throws: StartTestFailure.rollback) { try await retry.value }
        await #expect(throws: CancellationError.self) { try await starting.value }
        #expect(await child.status().state == .idle)
        #expect(await child.status().generation == 0)
        #expect(await operation.count() == 0)
        await child.close()
        await failed.close()
    }
}
