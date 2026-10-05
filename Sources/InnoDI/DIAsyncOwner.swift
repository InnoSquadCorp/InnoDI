import Foundation

/// Terminal admission boundary for the concrete scopes of one generated owner.
///
/// This actor retains no providers or services. A scope retains its admission
/// boundary, never the coordinator that owns the scope. Admission is a point
/// in time: work admitted before a competing close may win that race. Calls
/// admitted after close cannot start work or return even a cached service.
/// Cancellation is a scope-local transition and never pauses this boundary.
@_documentation(visibility: internal)
public actor _InnoDIAsyncAdmission {
    private var closed = false

    public init() {}

    func admit(providerID: String) throws {
        if closed {
            throw DIAsyncScopeError.closed(providerID: providerID)
        }
    }

    func isClosed() -> Bool { closed }

    func closeAdmission() {
        closed = true
    }
}

/// Lifecycle coordination for a container explicitly created with `makeOwned`.
///
/// Values stay in concrete `DIAsyncScope<Value>` instances. The existing
/// preparation plan supplies only graph validation and lifecycle traversal;
/// this coordinator never stores or resolves a type-erased service value.
@_documentation(visibility: internal)
public actor _InnoDIAsyncOwner {
    private let admission: _InnoDIAsyncAdmission
    private let plan: DIAsyncPreparationPlan
    private var cancellationTail: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    public init(
        admission: _InnoDIAsyncAdmission,
        nodes: [DIAsyncPreparationNode]
    ) throws {
        self.admission = admission
        self.plan = try DIAsyncPreparationPlan(nodes: nodes)
    }

    public func prepare(
        _ selectedProviderIDs: [String]
    ) async throws -> DIAsyncPreparationReport {
        try await admission.admit(providerID: admissionProviderID(selectedProviderIDs))
        return try await plan.prepare(selectedProviderIDs)
    }

    public func retry(
        _ selectedProviderIDs: [String]
    ) async throws -> DIAsyncPreparationReport {
        try await admission.admit(providerID: admissionProviderID(selectedProviderIDs))
        return try await plan.retry(selectedProviderIDs)
    }

    /// Runs one generated, concrete-scope cancellation body. Bodies execute in
    /// arrival order; distinct selections are never coalesced. Each scope's
    /// cancel transition is independent, not an atomic multi-provider operation.
    /// No admission is paused: selected ready values and unrelated work remain
    /// available, and an idle scope can start before or after its cancel turn.
    ///
    /// Cancelling the caller does not abandon its lifecycle operation. Once
    /// close begins, queued bodies do no further work, and their callers wait
    /// for the same terminal close completion.
    ///
    /// This is generated-code support, not an arbitrary callback API. The body
    /// must only cancel its captured concrete scopes and must not reenter owner
    /// lifecycle operations (in particular, close waits for this body).
    public func withCancellation(
        _ operation: @escaping @Sendable () async -> Void
    ) async {
        if let closeTask {
            await closeTask.value
            return
        }

        let predecessor = cancellationTail
        // An unstructured task deliberately makes lifecycle cleanup independent
        // of the requesting task's cancellation. It owns no service values.
        let task = Task {
            await predecessor?.value
            await self.performCancellation(operation)
        }
        cancellationTail = task
        await task.value
        if let closeTask {
            await closeTask.value
        }
    }

    /// Permanently closes admission before reverse-topological scope teardown.
    /// Every concurrent caller awaits the same close, including any in-flight
    /// cancellation body and retry reservation cleanup. Factories themselves
    /// are not drained: a factory that ignores cancellation can finish later,
    /// but its closed scope rejects that late result.
    public func close() async {
        if let closeTask {
            await closeTask.value
            return
        }

        let pendingCancellation = cancellationTail
        let task = Task { [admission, plan] in
            await admission.closeAdmission()
            // Queued bodies observe closeTask and skip their actions. Waiting
            // for this chain includes the active body without counting reads
            // or waiting for cancellation-ignoring provider factories.
            await pendingCancellation?.value
            await plan.closeAll()
        }
        // Publish before suspending so reentrant calls always join this task.
        closeTask = task
        await task.value
    }

    private func performCancellation(
        _ operation: @Sendable () async -> Void
    ) async {
        guard closeTask == nil else { return }
        await operation()
    }

    private func admissionProviderID(_ selectedProviderIDs: [String]) -> String {
        selectedProviderIDs.first ?? "_InnoDIAsyncOwner"
    }
}
