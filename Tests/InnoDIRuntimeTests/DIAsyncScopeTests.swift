import InnoDI
import Testing

private actor ControlledAsyncOperation {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultContinuation: CheckedContinuation<Int, Never>?

    func run() async -> Int {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeed(with value: Int) {
        resultContinuation?.resume(returning: value)
        resultContinuation = nil
    }
}

private actor RetryOperation {
    enum Failure: Error { case firstAttempt }
    private var attempts = 0

    func run() throws -> Int {
        attempts += 1
        if attempts == 1 { throw Failure.firstAttempt }
        return attempts
    }
}

private actor InvocationCounter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
    func snapshot() -> Int { value }
}

private enum PlannedFailure: Error { case unavailable }

@Suite("DIAsyncScope ownership")
struct DIAsyncScopeTests {
    @Test("waiter cancellation does not cancel shared owner work")
    func waiterCancellationIsIsolated() async throws {
        let operation = ControlledAsyncOperation()
        let scope = DIAsyncScope<Int>(providerID: "App.service") {
            await operation.run()
        }
        let cancelledWaiter = Task { try await scope.value() }
        let survivingWaiter = Task { try await scope.value() }

        await operation.waitUntilStarted()
        cancelledWaiter.cancel()
        do {
            _ = try await cancelledWaiter.value
            Issue.record("Cancelled waiter unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        }

        await operation.succeed(with: 42)
        #expect(try await survivingWaiter.value == 42)
        #expect(await scope.status().state == .ready)
    }

    @Test("owner close is idempotent and prevents new work")
    func closeCancelsScope() async throws {
        let operation = ControlledAsyncOperation()
        let scope = DIAsyncScope<Int>(providerID: "App.service") {
            await operation.run()
        }
        let waiter = Task { try await scope.value() }
        await operation.waitUntilStarted()

        await scope.close()
        await scope.close()
        await operation.succeed(with: 1)

        await #expect(throws: DIAsyncScopeError.closed(providerID: "App.service")) {
            try await waiter.value
        }
        await #expect(throws: DIAsyncScopeError.closed(providerID: "App.service")) {
            try await scope.value()
        }
        #expect(await scope.status().state == .closed)
    }

    @Test("retry starts a clean generation after failure")
    func retryUsesNewGeneration() async throws {
        let operation = RetryOperation()
        let scope = DIAsyncScope<Int>(providerID: "App.service") {
            try await operation.run()
        }

        await #expect(throws: RetryOperation.Failure.firstAttempt) {
            try await scope.value()
        }
        let failed = await scope.status()
        #expect(failed.state == .failed)
        #expect(failed.generation == 0)
        #expect(failed.errorDescription?.contains("Failure") == true)

        try await scope.retry()
        #expect(try await scope.value() == 2)
        let ready = await scope.status()
        #expect(ready.state == .ready)
        #expect(ready.generation == 1)
    }

    @Test("selected preparation reports partial failure and blocks downstream work")
    func selectedPreparationReportsProvenance() async throws {
        let rootCount = InvocationCounter()
        let failureCount = InvocationCounter()
        let downstreamCount = InvocationCounter()
        let unrelatedCount = InvocationCounter()
        let root = DIAsyncScope<Int>(providerID: "root") {
            await rootCount.increment()
        }
        let failure = DIAsyncScope<Int>(providerID: "failure") {
            _ = await failureCount.increment()
            throw PlannedFailure.unavailable
        }
        let downstream = DIAsyncScope<Int>(providerID: "downstream") {
            await downstreamCount.increment()
        }
        let unrelated = DIAsyncScope<Int>(providerID: "unrelated") {
            await unrelatedCount.increment()
        }
        let plan = try DIAsyncPreparationPlan(nodes: [
            DIAsyncPreparationNode(provider: root),
            DIAsyncPreparationNode(provider: failure, dependencies: ["root"]),
            DIAsyncPreparationNode(provider: downstream, dependencies: ["failure"]),
            DIAsyncPreparationNode(provider: unrelated),
        ])

        let report = try await plan.prepare(["downstream"])
        #expect(report.selectedProviderIDs == ["downstream"])
        #expect(report.entries.map(\.providerID) == ["root", "failure", "downstream"])
        #expect(report.entries.map(\.disposition) == [.ready, .failed, .blocked])
        #expect(report.entries.last?.blockingDependencies == ["failure"])
        #expect(!report.isReady)
        #expect(await rootCount.snapshot() == 1)
        #expect(await failureCount.snapshot() == 1)
        #expect(await downstreamCount.snapshot() == 0)
        #expect(await unrelatedCount.snapshot() == 0)
    }

    @Test("preparation plans fail closed for malformed graphs")
    func planValidationFailsClosed() {
        let first = DIAsyncScope<Int>(providerID: "first") { 1 }
        let duplicate = DIAsyncScope<Int>(providerID: "first") { 2 }
        #expect(throws: DIAsyncPreparationPlanError.duplicateProvider("first")) {
            _ = try DIAsyncPreparationPlan(nodes: [
                DIAsyncPreparationNode(provider: first),
                DIAsyncPreparationNode(provider: duplicate),
            ])
        }

        let cyclicA = DIAsyncScope<Int>(providerID: "a") { 1 }
        let cyclicB = DIAsyncScope<Int>(providerID: "b") { 2 }
        #expect(
            throws: DIAsyncPreparationPlanError.dependencyCycle(["a", "b", "a"])
        ) {
            _ = try DIAsyncPreparationPlan(nodes: [
                DIAsyncPreparationNode(provider: cyclicA, dependencies: ["b"]),
                DIAsyncPreparationNode(provider: cyclicB, dependencies: ["a"]),
            ])
        }
    }
}
