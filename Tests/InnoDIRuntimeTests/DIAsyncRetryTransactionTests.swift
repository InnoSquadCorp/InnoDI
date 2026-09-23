import Testing
@testable import InnoDI

private enum RetryTestFailure: Error { case expected }

private actor RetryTestGate {
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

private actor RetryOnceOperation {
    var count = 0
    func run() throws -> Int {
        count += 1
        if count == 1 { throw RetryTestFailure.expected }
        return count
    }
}

private struct NonTransactionalPreparation: DIAsyncPreparing {
    let scope: DIAsyncScope<Int>
    var providerID: String { scope.providerID }
    func status() async -> DIAsyncProviderStatus { await scope.status() }
    func prepare() async -> DIAsyncProviderStatus { await scope.prepare() }
    func retry() async throws { try await scope.retry() }
    func resetForSubgraphRetry() async throws { try await scope.resetForSubgraphRetry() }
    func close() async { await scope.close() }
}

private func resetGenerically<P: DIAsyncPreparing>(_ provider: P) async throws {
    try await provider.resetForSubgraphRetry()
}

@Suite("Async retry transaction", .timeLimit(.minutes(1)))
struct DIAsyncRetryTransactionTests {
    @Test("Concrete, existential, and generic reset dispatch have identical semantics",
          arguments: ["concrete", "existential", "generic"],
          [DIAsyncProviderStatus.State.idle, .running, .ready, .failed, .cancelled, .closed])
    func resetDispatch(call: String, state: DIAsyncProviderStatus.State) async throws {
        let started = RetryTestGate()
        let release = RetryTestGate()
        let scope = DIAsyncScope<Int>(providerID: "value") {
            if state == .failed { throw RetryTestFailure.expected }
            if state == .cancelled { throw CancellationError() }
            if state == .running {
                await started.open()
                await release.wait()
            }
            return 1
        }
        var pending: Task<Int, any Error>?
        switch state {
        case .running:
            pending = Task { try await scope.value() }
            await started.wait()
        case .ready, .failed, .cancelled:
            _ = await scope.prepare()
        case .closed: await scope.close()
        case .idle: break
        }
        do {
            switch call {
            case "concrete": try await scope.resetForSubgraphRetry()
            case "existential": try await (scope as any DIAsyncPreparing).resetForSubgraphRetry()
            default: try await resetGenerically(scope)
            }
            #expect(state != .closed && state != .running)
            #expect(await scope.status().generation == 1)
            #expect(await scope.status().state == .idle)
        } catch {
            if state == .closed {
                #expect(error as? DIAsyncScopeError == .closed(providerID: "value"))
            } else if state == .running {
                #expect(error as? DIAsyncPreparationPlanError == .retryWhileRunning(providerID: "value"))
            } else {
                Issue.record("Unexpected reset failure: \(error)")
            }
            #expect(await scope.status().generation == 0)
        }
        await scope.close()
        await release.open()
        _ = try? await pending?.value
    }

    @Test("Custom reset implementations fail closed before any generation changes")
    func rejectsNonTransactionalParticipant() async throws {
        let failed = DIAsyncScope<Int>(providerID: "failed") { throw RetryTestFailure.expected }
        let ready = DIAsyncScope(providerID: "ready") { 1 }
        _ = await failed.prepare()
        _ = await ready.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed),
            .init(provider: NonTransactionalPreparation(scope: ready), dependencies: ["failed"])
        ])
        await #expect(throws: DIAsyncPreparationPlanError.nonTransactionalProvider(providerID: "ready")) {
            try await plan.retry(["ready"])
        }
        #expect(await failed.status().generation == 0)
        #expect(await ready.status().generation == 0)
        #expect(await ready.status().state == .ready)
    }

    @Test("A closed descendant rejects the transaction without advancing its failed parent")
    func closedScopeAbortsWholeTransaction() async throws {
        let failed = DIAsyncScope<Int>(providerID: "failed") { throw RetryTestFailure.expected }
        let closed = DIAsyncScope(providerID: "closed") { 1 }
        _ = await failed.prepare()
        await closed.close()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: closed, dependencies: ["failed"])
        ])
        await #expect(throws: DIAsyncScopeError.closed(providerID: "closed")) {
            try await plan.retry(["closed"])
        }
        #expect(await failed.status().generation == 0)
        #expect(await closed.status().generation == 0)
        // A failed transaction released every reservation, including the
        // earlier lexicographic participant; these calls cannot hang.
        try await failed.retry()
        await failed.close()
    }

    @Test("Cancellation before commit releases reservations without any reset")
    func cancellationBeforeCommitIsNonMutating() async throws {
        let failed = DIAsyncScope<Int>(providerID: "failed") { throw RetryTestFailure.expected }
        let ready = DIAsyncScope(providerID: "ready") { 1 }
        _ = await failed.prepare()
        _ = await ready.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: ready, dependencies: ["failed"])
        ])
        let reserved = RetryTestGate()
        let release = RetryTestGate()
        let retry = Task {
            try await plan.retry(["ready"], beforeCommit: {
                await reserved.open()
                await release.wait()
            })
        }
        await reserved.wait()
        retry.cancel()
        await release.open()
        await #expect(throws: CancellationError.self) { try await retry.value }
        #expect(await failed.status().generation == 0)
        #expect(await ready.status().generation == 0)
        #expect(await ready.status().state == .ready)
        await failed.close()
        await ready.close()
    }

    @Test("Close during a reserved retry runs after all selected generations commit")
    func closeDuringReservedRetry() async throws {
        let failed = DIAsyncScope<Int>(providerID: "failed") { throw RetryTestFailure.expected }
        let ready = DIAsyncScope(providerID: "ready") { 1 }
        _ = await failed.prepare()
        _ = await ready.prepare()
        let plan = try DIAsyncPreparationPlan(nodes: [
            .init(provider: failed), .init(provider: ready, dependencies: ["failed"])
        ])
        let reserved = RetryTestGate()
        let release = RetryTestGate()
        let closeRequested = RetryTestGate()
        let retry = Task {
            try await plan.retry(["ready"], beforeCommit: {
                await reserved.open()
                await release.wait()
            })
        }
        await reserved.wait()
        let closing = Task {
            await closeRequested.open()
            await failed.close()
        }
        await closeRequested.wait()
        await release.open()
        _ = try await retry.value
        await closing.value
        #expect(await failed.status().generation == 1)
        #expect(await ready.status().generation == 1)
        #expect(await failed.status().state == .closed)
    }

    @Test("Overlapping plans use a stable reservation order", arguments: 0..<20)
    func overlappingPlans(_ iteration: Int) async throws {
        let operation = RetryOnceOperation()
        let first = DIAsyncScope(providerID: "a") { try await operation.run() }
        let second = DIAsyncScope(providerID: "b") { 2 }
        _ = await first.prepare()
        _ = await second.prepare()
        let left = try DIAsyncPreparationPlan(nodes: [
            .init(provider: first), .init(provider: second, dependencies: ["a"])
        ])
        let right = try DIAsyncPreparationPlan(nodes: [
            .init(provider: second, dependencies: ["a"]), .init(provider: first)
        ])
        async let leftResult = try? left.retry(["b"])
        async let rightResult = try? right.retry(["b"])
        let results = await [leftResult, rightResult]
        #expect(results.compactMap { $0 }.count == 1)
        #expect(await first.status().generation == 1)
        #expect(await second.status().generation == 1)
        #expect(await first.status().state == .ready)
        #expect(await second.status().state == .ready)
    }
}
