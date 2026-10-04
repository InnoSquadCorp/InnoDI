import Foundation

/// Observable lifecycle state for an InnoDI-owned asynchronous provider.
public struct DIAsyncProviderStatus: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case idle
        case running
        case ready
        case failed
        case cancelled
        case closed
    }

    public let providerID: String
    public let generation: Int
    public let state: State
    public let errorDescription: String?

    public init(
        providerID: String,
        generation: Int,
        state: State,
        errorDescription: String? = nil
    ) {
        self.providerID = providerID
        self.generation = generation
        self.state = state
        self.errorDescription = errorDescription
    }
}

public enum DIAsyncScopeError: Error, Equatable, Sendable {
    case closed(providerID: String)
    case retryRequiresFailure(providerID: String)
}

/// Type-erased preparation surface used by ``DIAsyncPreparationPlan``.
public protocol DIAsyncPreparing: Sendable {
    var providerID: String { get }
    func status() async -> DIAsyncProviderStatus
    func prepare() async -> DIAsyncProviderStatus
    func retry() async throws
    func resetForSubgraphRetry() async throws
    func close() async
}

public extension DIAsyncPreparing {
    /// Compatibility default for manually resetting a custom provider.
    /// Delegates to failure-only retry; transactional plan retry requires a
    /// library-owned scope and does not call this default implementation.
    func resetForSubgraphRetry() async throws {
        try await retry()
    }
}

public enum DIAsyncPreparationPlanError: Error, Equatable, Sendable {
    case duplicateProvider(String)
    case unknownProvider(String)
    case unknownDependency(providerID: String, dependencyID: String)
    case dependencyCycle([String])
    case retryRequiresFailure(selectedProviderIDs: [String])
    case retryWhileRunning(providerID: String)
    case nonTransactionalProvider(providerID: String)
}

/// Only library-owned scopes can guarantee that close, value, status, and
/// standalone retry all respect the same reservation. Custom preparation
/// providers cannot opt in accidentally via a default protocol witness.
private protocol DIAsyncRetryParticipant: DIAsyncPreparing {
    func reserveForRetry(_ token: UUID) async throws -> DIAsyncProviderStatus
    func commitReservedRetry(_ token: UUID) async
    func releaseRetryReservation(_ token: UUID) async
}

/// One provider and its explicit asynchronous preparation dependencies.
public struct DIAsyncPreparationNode: Sendable {
    public let provider: any DIAsyncPreparing
    public let dependencies: [String]

    public init(
        provider: any DIAsyncPreparing,
        dependencies: [String] = []
    ) {
        self.provider = provider
        self.dependencies = dependencies
    }
}

/// One deterministic entry in a selected preparation report.
public struct DIAsyncPreparationEntry: Equatable, Sendable {
    public enum Disposition: String, Equatable, Sendable {
        case ready
        case failed
        case blocked
        case running
        case cancelled
        case closed
    }

    public let providerID: String
    public let status: DIAsyncProviderStatus
    public let disposition: Disposition
    public let blockingDependencies: [String]

    public init(
        providerID: String,
        status: DIAsyncProviderStatus,
        disposition: Disposition,
        blockingDependencies: [String] = []
    ) {
        self.providerID = providerID
        self.status = status
        self.disposition = disposition
        self.blockingDependencies = blockingDependencies
    }
}

/// Result of preparing a selected provider subgraph.
public struct DIAsyncPreparationReport: Equatable, Sendable {
    public let selectedProviderIDs: [String]
    public let entries: [DIAsyncPreparationEntry]

    public init(
        selectedProviderIDs: [String],
        entries: [DIAsyncPreparationEntry]
    ) {
        self.selectedProviderIDs = selectedProviderIDs
        self.entries = entries
    }

    public var isReady: Bool {
        entries.allSatisfy { $0.disposition == .ready }
    }

    /// Requires every selected preparation entry to be ready.
    ///
    /// Preparation records provider failures in this report rather than
    /// throwing them. Use this check for proceed-or-fail callers. The error
    /// preserves structured status and blocking dependencies, not arbitrary
    /// factory error payloads. This synchronous check does not inspect the
    /// calling task's cancellation state.
    public func requireReady() throws {
        guard isReady else { throw DIAsyncPreparationFailure(report: self) }
    }
}

/// Selected asynchronous providers did not all reach readiness.
///
/// Inspect the report to distinguish failed, blocked, cancelled and closed
/// providers. While a scope remains open, its provider read can still throw
/// the original factory error. A prepared operation closes before throwing
/// this failure, so its escaped view instead reports closed. This error keeps
/// only the preparation snapshot, not arbitrary factory error payloads.
public struct DIAsyncPreparationFailure: Error, Equatable, Sendable {
    public let report: DIAsyncPreparationReport

    public init(report: DIAsyncPreparationReport) {
        self.report = report
    }
}

/// Validated, explicit dependency graph for selected asynchronous preparation.
///
/// The plan prepares only the selected providers and their transitive
/// dependencies. A failed dependency leaves downstream providers idle and
/// records them as blocked instead of starting work that cannot succeed.
public struct DIAsyncPreparationPlan: Sendable {
    private let providers: [String: any DIAsyncPreparing]
    private let dependencies: [String: [String]]
    private let topologicalOrder: [String]

    public init(nodes: [DIAsyncPreparationNode]) throws {
        var providers: [String: any DIAsyncPreparing] = [:]
        var dependencies: [String: [String]] = [:]
        var declarationOrder: [String] = []
        for node in nodes {
            let id = node.provider.providerID
            guard providers[id] == nil else {
                throw DIAsyncPreparationPlanError.duplicateProvider(id)
            }
            providers[id] = node.provider
            dependencies[id] = node.dependencies
            declarationOrder.append(id)
        }
        for id in declarationOrder {
            for dependency in dependencies[id, default: []]
                where providers[dependency] == nil {
                throw DIAsyncPreparationPlanError.unknownDependency(
                    providerID: id,
                    dependencyID: dependency
                )
            }
        }

        self.topologicalOrder = try Self.makeTopologicalOrder(
            declarationOrder: declarationOrder,
            dependencies: dependencies
        )
        self.providers = providers
        self.dependencies = dependencies
    }

    public func prepare(
        _ selectedProviderIDs: [String]
    ) async throws -> DIAsyncPreparationReport {
        let selected = try transitiveSelection(selectedProviderIDs)
        var entries: [DIAsyncPreparationEntry] = []
        var dispositionByID: [String: DIAsyncPreparationEntry.Disposition] = [:]

        for id in topologicalOrder where selected.contains(id) {
            guard let provider = providers[id] else { continue }
            let blockers = dependencies[id, default: []].filter {
                dispositionByID[$0] != .ready
            }
            if !blockers.isEmpty {
                let status = await provider.status()
                entries.append(
                    DIAsyncPreparationEntry(
                        providerID: id,
                        status: status,
                        disposition: .blocked,
                        blockingDependencies: blockers
                    )
                )
                dispositionByID[id] = .blocked
                continue
            }

            let status = await provider.prepare()
            let disposition: DIAsyncPreparationEntry.Disposition
            switch status.state {
            case .ready: disposition = .ready
            case .failed: disposition = .failed
            case .cancelled: disposition = .cancelled
            case .closed: disposition = .closed
            case .idle, .running: disposition = .running
            }
            entries.append(
                DIAsyncPreparationEntry(
                    providerID: id,
                    status: status,
                    disposition: disposition
                )
            )
            dispositionByID[id] = disposition
        }

        return DIAsyncPreparationReport(
            selectedProviderIDs: selectedProviderIDs,
            entries: entries
        )
    }

    /// Retries every failed or cancelled provider in the selected subgraph,
    /// together with only its selected downstream dependants.
    ///
    /// Ready parent dependencies outside that affected child subgraph retain
    /// their values and generations. All selected library-owned scopes are
    /// reserved before preflight. Commit cannot fail after the first reset;
    /// competing close/value/retry/status calls wait for reservation release.
    /// Custom `DIAsyncPreparing` implementations support prepare/close, but
    /// plan retry rejects them before mutation with `nonTransactionalProvider`.
    public func retry(
        _ selectedProviderIDs: [String]
    ) async throws -> DIAsyncPreparationReport {
        try await retry(selectedProviderIDs, beforeCommit: nil)
    }

    // Internal synchronization seam for deterministic transaction regressions.
    func retry(
        _ selectedProviderIDs: [String],
        beforeCommit: (@Sendable () async throws -> Void)?
    ) async throws -> DIAsyncPreparationReport {
        let selected = try transitiveSelection(selectedProviderIDs)
        var participants: [String: any DIAsyncRetryParticipant] = [:]
        // Verify every participant before acquiring or changing anything.
        for id in selected.sorted() {
            guard let participant = providers[id] as? any DIAsyncRetryParticipant else {
                throw DIAsyncPreparationPlanError.nonTransactionalProvider(providerID: id)
            }
            participants[id] = participant
        }
        let token = UUID()
        var reserved: [any DIAsyncRetryParticipant] = []
        var statusByID: [String: DIAsyncProviderStatus] = [:]
        do {
            // A shared provider has the same immutable ID in every plan.
            // Total ordering prevents overlapping plans from deadlocking.
            for id in selected.sorted() {
                guard let participant = participants[id] else { continue }
                statusByID[id] = try await participant.reserveForRetry(token)
                reserved.append(participant)
            }

            let retryRoots = Set(statusByID.compactMap { id, status in
                switch status.state {
                case .failed, .cancelled: id
                case .idle, .running, .ready, .closed: nil
                }
            })
            guard !retryRoots.isEmpty else {
                throw DIAsyncPreparationPlanError.retryRequiresFailure(
                    selectedProviderIDs: selectedProviderIDs
                )
            }

            var retrySet = retryRoots
            for id in topologicalOrder where selected.contains(id) {
                if dependencies[id, default: []].contains(where: retrySet.contains) {
                    retrySet.insert(id)
                }
            }

            for id in topologicalOrder where retrySet.contains(id) {
                guard let status = statusByID[id] else { continue }
                switch status.state {
                case .running:
                    throw DIAsyncPreparationPlanError.retryWhileRunning(providerID: id)
                case .closed:
                    throw DIAsyncScopeError.closed(providerID: id)
                case .idle, .ready, .failed, .cancelled:
                    break
                }
            }

            try await beforeCommit?()
            try Task.checkCancellation()
            // From here through release, no user code or throwing reset is
            // called. Cancellation cannot strand a partially committed set.
            for id in topologicalOrder.reversed() where retrySet.contains(id) {
                await participants[id]?.commitReservedRetry(token)
            }
        } catch {
            for participant in reserved.reversed() {
                await participant.releaseRetryReservation(token)
            }
            throw error
        }
        for participant in reserved.reversed() {
            await participant.releaseRetryReservation(token)
        }
        return try await prepare(selectedProviderIDs)
    }

    public func close(_ selectedProviderIDs: [String]) async throws {
        let selected = try transitiveSelection(selectedProviderIDs)
        for id in topologicalOrder.reversed() where selected.contains(id) {
            await providers[id]?.close()
        }
    }

    // Owner cleanup already owns the validated complete graph. It must not
    // perform another throwing selection step after closing admission.
    func closeAll() async {
        for id in topologicalOrder.reversed() {
            await providers[id]?.close()
        }
    }

    private func transitiveSelection(
        _ requested: [String]
    ) throws -> Set<String> {
        var selected = Set<String>()
        var pending = requested
        while let id = pending.popLast() {
            guard providers[id] != nil else {
                throw DIAsyncPreparationPlanError.unknownProvider(id)
            }
            guard selected.insert(id).inserted else { continue }
            pending.append(contentsOf: dependencies[id, default: []])
        }
        return selected
    }

    private static func makeTopologicalOrder(
        declarationOrder: [String],
        dependencies: [String: [String]]
    ) throws -> [String] {
        enum Mark { case visiting, visited }
        var marks: [String: Mark] = [:]
        var path: [String] = []
        var result: [String] = []
        // Keep traversal state on the heap. Recursive DFS exhausts the native
        // stack on a valid long chain before it can return a plan or diagnostic.
        struct Frame {
            let id: String
            var nextDependency = 0
        }
        var stack: [Frame] = []
        for id in declarationOrder where marks[id] == nil {
            marks[id] = .visiting
            path.append(id)
            stack.append(Frame(id: id))
            while let frame = stack.last {
                let children = dependencies[frame.id, default: []]
                guard frame.nextDependency < children.count else {
                    stack.removeLast()
                    path.removeLast()
                    marks[frame.id] = .visited
                    result.append(frame.id)
                    continue
                }
                let dependency = children[frame.nextDependency]
                stack[stack.count - 1].nextDependency += 1
                if marks[dependency] == .visited { continue }
                if marks[dependency] == .visiting {
                    let cycleStart = path.firstIndex(of: dependency) ?? 0
                    throw DIAsyncPreparationPlanError.dependencyCycle(
                        Array(path[cycleStart...]) + [dependency]
                    )
                }
                marks[dependency] = .visiting
                path.append(dependency)
                stack.append(Frame(id: dependency))
            }
        }
        return result
    }
}

/// Owns and coalesces one asynchronous provider task.
///
/// Cancelling a caller cancels only that wait. Calling ``close()`` cancels the
/// owned task, resumes every waiter, and permanently prevents new work.
/// It also releases the scope's factory captures. Already-running work retains
/// its own captures until it returns, even if it ignores cancellation.
/// ``retry()`` is available after failure and advances to a clean generation.
/// ``start()`` admits work without waiting for its value or adding a waiter.
public actor DIAsyncScope<Value: Sendable>: DIAsyncPreparing, DIAsyncRetryParticipant {
    public typealias Operation = @Sendable () async throws -> Value

    // Allocate only for explicit ready overrides. Keeping the reusable seed
    // behind a typed immutable box avoids adding another inline Value-sized
    // field to every ordinary factory-backed scope.
    private final class Seed: Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    private enum Source {
        case operation(Operation)
        case value(Seed)
    }

    private enum Phase {
        case idle
        case running
        case ready(Value)
        case failed(any Error)
        case cancelled
        case closed
    }

    public nonisolated let providerID: String
    private let admission: _InnoDIAsyncAdmission?
    private var source: Source?
    private var generation = 0
    private var phase: Phase = .idle
    private var ownedTask: Task<Value, any Error>?
    private var waiters: [UUID: CheckedContinuation<Value, any Error>] = [:]
    private var retryReservation: UUID?
    private var reservationWaiters: [CheckedContinuation<Void, Never>] = []

    public init(providerID: String, operation: @escaping Operation) {
        self.providerID = providerID
        self.admission = nil
        self.source = .operation(operation)
    }

    /// Creates a factory-backed scope bound to a shared owner admission gate.
    public init(
        providerID: String,
        admission: _InnoDIAsyncAdmission,
        operation: @escaping Operation
    ) {
        self.providerID = providerID
        self.admission = admission
        self.source = .operation(operation)
    }

    /// Creates an already-ready scope backed by a concrete override value.
    ///
    /// A subgraph reset advances to an idle generation. Its next ``start()``
    /// or ``value()`` restores the same value without invoking a factory or
    /// creating a task. ``close()`` releases both the cached and reusable value.
    public init(value: Value, providerID: String) {
        self.providerID = providerID
        self.admission = nil
        self.source = .value(Seed(value))
        self.phase = .ready(value)
    }

    /// Creates an already-ready override bound to a shared owner admission gate.
    public init(
        value: Value,
        providerID: String,
        admission: _InnoDIAsyncAdmission
    ) {
        self.providerID = providerID
        self.admission = admission
        self.source = .value(Seed(value))
        self.phase = .ready(value)
    }

    public func status() async -> DIAsyncProviderStatus {
        await waitForRetryReservation()
        return currentStatus()
    }

    private func currentStatus() -> DIAsyncProviderStatus {
        switch phase {
        case .idle:
            makeStatus(.idle)
        case .running:
            makeStatus(.running)
        case .ready:
            makeStatus(.ready)
        case .failed(let error):
            makeStatus(.failed, error: error)
        case .cancelled:
            makeStatus(.cancelled)
        case .closed:
            makeStatus(.closed)
        }
    }

    public func value() async throws -> Value {
        try Task.checkCancellation()
        try await admission?.admit(providerID: providerID)
        return try await valueAfterAdmission()
    }

    private func valueAfterAdmission() async throws -> Value {
        await waitForRetryReservation()
        try Task.checkCancellation()
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(waiterID: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        }
    }

    /// Admits this generation's work without waiting for readiness.
    ///
    /// Waits only for owner admission and an in-progress retry reservation.
    /// An idle factory starts one owned task; concurrent starts and value
    /// requests share that task.
    /// Ready, failed, and cancelled generations return their cached status
    /// without an implicit retry. A closed scope throws
    /// ``DIAsyncScopeError/closed(providerID:)``.
    ///
    /// Cancellation before admission prevents work from starting. Once work
    /// is admitted, cancelling this caller does not cancel the owned task.
    public func start() async throws -> DIAsyncProviderStatus {
        try Task.checkCancellation()
        try await admission?.admit(providerID: providerID)
        await waitForRetryReservation()
        try Task.checkCancellation()
        try startAdmittedWork()
        return currentStatus()
    }

    public func prepare() async -> DIAsyncProviderStatus {
        do {
            try Task.checkCancellation()
            do {
                try await admission?.admit(providerID: providerID)
            } catch let error as DIAsyncScopeError
                where error == .closed(providerID: providerID) {
                // Admission can close before this scope's cleanup runs. Keep
                // that outcome separate from a factory throwing the same
                // public error, which remains a cached provider failure.
                try Task.checkCancellation()
                await waitForRetryReservation()
                return makeStatus(.closed)
            }
            _ = try await valueAfterAdmission()
        } catch is CancellationError {
            await waitForRetryReservation()
            return makeStatus(.cancelled)
        } catch {
            // The status carries bounded provenance without retaining or
            // serializing arbitrary user error payloads.
        }
        return await status()
    }

    public func retry() async throws {
        try await admission?.admit(providerID: providerID)
        await waitForRetryReservation()
        try Task.checkCancellation()
        switch phase {
        case .failed, .cancelled:
            generation += 1
            phase = .idle
            ownedTask = nil
        case .idle, .running, .ready, .closed:
            throw DIAsyncScopeError.retryRequiresFailure(
                providerID: providerID
            )
        }
    }

    public func resetForSubgraphRetry() async throws {
        try await admission?.admit(providerID: providerID)
        await waitForRetryReservation()
        try Task.checkCancellation()
        switch phase {
        case .idle, .ready, .failed, .cancelled:
            generation += 1
            phase = .idle
            ownedTask = nil
        case .running:
            throw DIAsyncPreparationPlanError.retryWhileRunning(
                providerID: providerID
            )
        case .closed:
            throw DIAsyncScopeError.closed(providerID: providerID)
        }
    }

    /// Cancels running work while retaining its source for retry.
    ///
    /// Running value waiters resume with `CancellationError`. Idle scopes,
    /// ready values, cached failures, and closed scopes remain unchanged.
    /// Cancellation does not advance the generation; ``retry()`` starts a
    /// clean generation after running work was cancelled.
    public func cancel() async {
        await waitForRetryReservation()
        switch phase {
        case .running:
            phase = .cancelled
            ownedTask?.cancel()
            ownedTask = nil
            let currentWaiters = waiters.values
            waiters.removeAll(keepingCapacity: false)
            for waiter in currentWaiters {
                waiter.resume(throwing: CancellationError())
            }
        case .idle, .ready, .failed, .cancelled, .closed:
            break
        }
    }

    public func close() async {
        await waitForRetryReservation()
        guard case .closed = phase else {
            phase = .closed
            source = nil
            ownedTask?.cancel()
            ownedTask = nil
            let currentWaiters = waiters.values
            waiters.removeAll(keepingCapacity: false)
            for waiter in currentWaiters {
                waiter.resume(
                    throwing: DIAsyncScopeError.closed(
                        providerID: providerID
                    )
                )
            }
            return
        }
    }

    private func waitForRetryReservation() async {
        while retryReservation != nil {
            await withCheckedContinuation { reservationWaiters.append($0) }
        }
    }

    fileprivate func reserveForRetry(_ token: UUID) async throws -> DIAsyncProviderStatus {
        try Task.checkCancellation()
        try await admission?.admit(providerID: providerID)
        await waitForRetryReservation()
        try Task.checkCancellation()
        retryReservation = token
        return currentStatus()
    }

    fileprivate func commitReservedRetry(_ token: UUID) {
        // Only the owning plan calls this after validating the reserved state.
        precondition(retryReservation == token)
        generation += 1
        phase = .idle
        ownedTask = nil
    }

    fileprivate func releaseRetryReservation(_ token: UUID) {
        precondition(retryReservation == token)
        retryReservation = nil
        let pending = reservationWaiters
        reservationWaiters.removeAll()
        for waiter in pending { waiter.resume() }
    }

    private func register(
        waiterID: UUID,
        continuation: CheckedContinuation<Value, any Error>
    ) {
        // This continuation body runs synchronously on this actor, in the
        // caller's task. A cancellation delivered before registration is
        // observable here; one delivered after this check cannot run the
        // actor-isolated handler until registration finishes. No tombstones
        // are needed for handlers arriving after completion or a retry.
        if Task.isCancelled {
            continuation.resume(throwing: CancellationError())
            return
        }
        do {
            try startAdmittedWork()
        } catch {
            continuation.resume(throwing: error)
            return
        }
        switch phase {
        case .ready(let value):
            continuation.resume(returning: value)
        case .failed(let error):
            continuation.resume(throwing: error)
        case .cancelled:
            continuation.resume(throwing: CancellationError())
        case .closed:
            continuation.resume(
                throwing: DIAsyncScopeError.closed(providerID: providerID)
            )
        case .idle, .running:
            waiters[waiterID] = continuation
        }
    }

    private func startAdmittedWork() throws {
        switch phase {
        case .idle:
            switch source {
            case .operation(let operation):
                startOwnedTask(operation: operation)
            case .value(let seed):
                phase = .ready(seed.value)
            case nil:
                throw DIAsyncScopeError.closed(providerID: providerID)
            }
        case .closed:
            throw DIAsyncScopeError.closed(providerID: providerID)
        case .running, .ready, .failed, .cancelled:
            break
        }
    }

    // Internal so cancellation delivery after completion/reset can be tested
    // deterministically without depending on executor scheduling.
    func cancel(waiterID: UUID) {
        guard let waiter = waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(throwing: CancellationError())
    }

    private func startOwnedTask(operation: @escaping Operation) {
        phase = .running
        let taskGeneration = generation
        let task = Task { try await operation() }
        ownedTask = task
        Task {
            do {
                await finish(
                    generation: taskGeneration,
                    result: .success(try await task.value)
                )
            } catch {
                await finish(
                    generation: taskGeneration,
                    result: .failure(error)
                )
            }
        }
    }

    private func finish(
        generation completedGeneration: Int,
        result: Result<Value, any Error>
    ) async {
        await waitForRetryReservation()
        guard completedGeneration == generation,
              case .running = phase else {
            return
        }
        ownedTask = nil
        let currentWaiters = waiters.values
        waiters.removeAll(keepingCapacity: false)
        switch result {
        case .success(let value):
            phase = .ready(value)
            for waiter in currentWaiters {
                waiter.resume(returning: value)
            }
        case .failure(let error):
            if error is CancellationError {
                phase = .cancelled
            } else {
                phase = .failed(error)
            }
            for waiter in currentWaiters {
                waiter.resume(throwing: error)
            }
        }
    }

    private func makeStatus(
        _ state: DIAsyncProviderStatus.State,
        error: (any Error)? = nil
    ) -> DIAsyncProviderStatus {
        DIAsyncProviderStatus(
            providerID: providerID,
            generation: generation,
            state: state,
            errorDescription: error.map { String(reflecting: type(of: $0)) }
        )
    }
}
