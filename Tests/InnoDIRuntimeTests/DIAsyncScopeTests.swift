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

private actor CancellationRetryOperation {
    private var attempts = 0

    func run() throws -> Int {
        attempts += 1
        if attempts == 1 { throw CancellationError() }
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

private struct ChildValue: Equatable, Sendable {
    let parentIdentity: Int
    let childIdentity: Int
}

private struct DownstreamValue: Equatable, Sendable {
    let parentIdentity: Int
    let childIdentity: Int
    let downstreamIdentity: Int
}

private actor SubgraphProbe {
    private var parentCreations = 0
    private var childCreations = 0
    private var downstreamCreations = 0

    func makeParent() -> Int {
        parentCreations += 1
        return parentCreations
    }

    func makeChild(parentIdentity: Int) throws -> ChildValue {
        childCreations += 1
        if childCreations < 3 { throw PlannedFailure.unavailable }
        return ChildValue(
            parentIdentity: parentIdentity,
            childIdentity: childCreations
        )
    }

    func makeDownstream(child: ChildValue) -> DownstreamValue {
        downstreamCreations += 1
        return DownstreamValue(
            parentIdentity: child.parentIdentity,
            childIdentity: child.childIdentity,
            downstreamIdentity: downstreamCreations
        )
    }

    func snapshot() -> (parent: Int, child: Int, downstream: Int) {
        (parentCreations, childCreations, downstreamCreations)
    }
}

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
        let cancelledPreparation = Task {
            while !Task.isCancelled { await Task.yield() }
            return await scope.prepare()
        }
        cancelledPreparation.cancel()
        cancelledWaiter.cancel()
        do {
            _ = try await cancelledWaiter.value
            Issue.record("Cancelled waiter unexpectedly succeeded")
        } catch is CancellationError {
            // Expected.
        }
        #expect(await cancelledPreparation.value.state == .cancelled)

        await operation.succeed(with: 42)
        #expect(try await survivingWaiter.value == 42)
        #expect(await scope.status().state == .ready)
    }

    @Test("pre-cancelled waits and preparation never start a factory")
    func preCancelledRequestsDoNotStartWork() async throws {
        let count = InvocationCounter()
        let scope = DIAsyncScope<Int>(providerID: "App.service") {
            await count.increment()
        }
        let plan = try DIAsyncPreparationPlan(nodes: [
            DIAsyncPreparationNode(provider: scope),
        ])

        let waiter = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await scope.value()
        }
        waiter.cancel()
        await #expect(throws: CancellationError.self) {
            try await waiter.value
        }

        let preparation = Task {
            while !Task.isCancelled { await Task.yield() }
            return try await plan.prepare(["App.service"])
        }
        preparation.cancel()
        let report = try await preparation.value

        #expect(report.entries.map(\.disposition) == [.cancelled])
        #expect(report.entries.first?.status.state == .cancelled)
        #expect(await scope.status().state == .idle)
        #expect(await count.snapshot() == 0)

        #expect(try await scope.value() == 1)
        #expect(await count.snapshot() == 1)
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

    @Test("owned cancellation is observable and retryable")
    func ownedCancellationCanRetry() async throws {
        let operation = CancellationRetryOperation()
        let scope = DIAsyncScope<Int>(providerID: "App.service") {
            try await operation.run()
        }

        await #expect(throws: CancellationError.self) {
            try await scope.value()
        }
        let cancelled = await scope.status()
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.errorDescription == nil)

        try await scope.retry()
        #expect(try await scope.value() == 2)
        #expect(await scope.status().generation == 1)
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
        await #expect(throws: PlannedFailure.unavailable) {
            try await failure.value()
        }
        #expect(
            report.entries[1].status.errorDescription?
                .contains("PlannedFailure") == true
        )
    }

    @Test("subgraph retry replaces failed child generations only")
    func retryReplacesFailedChildSubgraph() async throws {
        let probe = SubgraphProbe()
        let parent = DIAsyncScope<Int>(providerID: "parent") {
            await probe.makeParent()
        }
        let child = DIAsyncScope<ChildValue>(providerID: "child") {
            let parentIdentity = try await parent.value()
            return try await probe.makeChild(parentIdentity: parentIdentity)
        }
        let downstream = DIAsyncScope<DownstreamValue>(providerID: "downstream") {
            let childValue = try await child.value()
            return await probe.makeDownstream(child: childValue)
        }
        let plan = try DIAsyncPreparationPlan(nodes: [
            DIAsyncPreparationNode(provider: parent),
            DIAsyncPreparationNode(provider: child, dependencies: ["parent"]),
            DIAsyncPreparationNode(provider: downstream, dependencies: ["child"]),
        ])

        let failed = try await plan.prepare(["downstream"])
        #expect(failed.entries.map(\.disposition) == [.ready, .failed, .blocked])
        #expect(await parent.status().generation == 0)
        #expect(await child.status().generation == 0)
        #expect(await downstream.status().generation == 0)

        let failedAgain = try await plan.retry(["downstream"])
        #expect(failedAgain.entries.map(\.disposition) == [.ready, .failed, .blocked])
        #expect(await parent.status().generation == 0)
        #expect(await child.status().generation == 1)
        #expect(await downstream.status().generation == 1)

        let recovered = try await plan.retry(["downstream"])
        #expect(recovered.entries.map(\.disposition) == [.ready, .ready, .ready])
        #expect(await parent.status().generation == 0)
        #expect(await child.status().generation == 2)
        #expect(await downstream.status().generation == 2)
        #expect(
            try await downstream.value()
                == DownstreamValue(
                    parentIdentity: 1,
                    childIdentity: 3,
                    downstreamIdentity: 1
                )
        )
        let counts = await probe.snapshot()
        #expect(counts.parent == 1)
        #expect(counts.child == 3)
        #expect(counts.downstream == 1)
    }

    @Test("subgraph retry preflights running descendants without partial reset")
    func retryPreflightIsNonMutating() async throws {
        let runningOperation = ControlledAsyncOperation()
        let failed = DIAsyncScope<Int>(providerID: "failed") {
            throw PlannedFailure.unavailable
        }
        let downstream = DIAsyncScope<Int>(providerID: "downstream") {
            await runningOperation.run()
        }
        let plan = try DIAsyncPreparationPlan(nodes: [
            DIAsyncPreparationNode(provider: failed),
            DIAsyncPreparationNode(provider: downstream, dependencies: ["failed"]),
        ])
        let externalWaiter = Task { try await downstream.value() }
        await runningOperation.waitUntilStarted()

        let report = try await plan.prepare(["downstream"])
        #expect(report.entries.map(\.disposition) == [.failed, .blocked])
        await #expect(
            throws: DIAsyncPreparationPlanError.retryWhileRunning(
                providerID: "downstream"
            )
        ) {
            try await plan.retry(["downstream"])
        }
        #expect(await failed.status().generation == 0)
        #expect(await downstream.status().generation == 0)

        await runningOperation.succeed(with: 7)
        #expect(try await externalWaiter.value == 7)
    }

    @Test("one hundred waiters share failure retry and close boundaries")
    func waiterRetryCloseStress() async throws {
        let operation = RetryOperation()
        let scope = DIAsyncScope<Int>(providerID: "App.stress") {
            try await operation.run()
        }

        let failedWaiters = (0..<100).map { _ in
            Task { try await scope.value() }
        }
        for waiter in failedWaiters {
            await #expect(throws: RetryOperation.Failure.firstAttempt) {
                try await waiter.value
            }
        }

        try await scope.retry()
        let recoveredWaiters = (0..<100).map { _ in
            Task { try await scope.value() }
        }
        for waiter in recoveredWaiters {
            #expect(try await waiter.value == 2)
        }

        await scope.close()
        let closedWaiters = (0..<100).map { _ in
            Task { try await scope.value() }
        }
        for waiter in closedWaiters {
            await #expect(
                throws: DIAsyncScopeError.closed(providerID: "App.stress")
            ) {
                try await waiter.value
            }
        }
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
