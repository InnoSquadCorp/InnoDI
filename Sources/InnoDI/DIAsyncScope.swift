import Foundation

/// Observable lifecycle state for an InnoDI-owned asynchronous provider.
public struct DIAsyncProviderStatus: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case idle
        case running
        case ready
        case failed
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
    func close() async
}

public enum DIAsyncPreparationPlanError: Error, Equatable, Sendable {
    case duplicateProvider(String)
    case unknownProvider(String)
    case unknownDependency(providerID: String, dependencyID: String)
    case dependencyCycle([String])
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

    public func close(_ selectedProviderIDs: [String]) async throws {
        let selected = try transitiveSelection(selectedProviderIDs)
        for id in topologicalOrder.reversed() where selected.contains(id) {
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

        func visit(_ id: String) throws {
            if marks[id] == .visited { return }
            if marks[id] == .visiting {
                let cycleStart = path.firstIndex(of: id) ?? 0
                throw DIAsyncPreparationPlanError.dependencyCycle(
                    Array(path[cycleStart...]) + [id]
                )
            }
            marks[id] = .visiting
            path.append(id)
            for dependency in dependencies[id, default: []] {
                try visit(dependency)
            }
            _ = path.popLast()
            marks[id] = .visited
            result.append(id)
        }

        for id in declarationOrder { try visit(id) }
        return result
    }
}

/// Owns and coalesces one asynchronous provider task.
///
/// Cancelling a caller cancels only that wait. Calling ``close()`` cancels the
/// owned task, resumes every waiter, and permanently prevents new work.
/// ``retry()`` is available after failure and advances to a clean generation.
public actor DIAsyncScope<Value: Sendable>: DIAsyncPreparing {
    public typealias Operation = @Sendable () async throws -> Value

    private enum Phase {
        case idle
        case running
        case ready(Value)
        case failed(any Error)
        case closed
    }

    public nonisolated let providerID: String
    private let operation: Operation
    private var generation = 0
    private var phase: Phase = .idle
    private var ownedTask: Task<Value, any Error>?
    private var waiters: [UUID: CheckedContinuation<Value, any Error>] = [:]
    private var cancelledWaiters: Set<UUID> = []

    public init(providerID: String, operation: @escaping Operation) {
        self.providerID = providerID
        self.operation = operation
    }

    public func status() -> DIAsyncProviderStatus {
        switch phase {
        case .idle:
            makeStatus(.idle)
        case .running:
            makeStatus(.running)
        case .ready:
            makeStatus(.ready)
        case .failed(let error):
            makeStatus(.failed, error: error)
        case .closed:
            makeStatus(.closed)
        }
    }

    public func value() async throws -> Value {
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(waiterID: waiterID, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(waiterID: waiterID) }
        }
    }

    public func prepare() async -> DIAsyncProviderStatus {
        do {
            _ = try await value()
        } catch {
            // The status carries bounded provenance without retaining or
            // serializing arbitrary user error payloads.
        }
        return status()
    }

    public func retry() throws {
        guard case .failed = phase else {
            throw DIAsyncScopeError.retryRequiresFailure(
                providerID: providerID
            )
        }
        generation += 1
        phase = .idle
        ownedTask = nil
    }

    public func close() {
        guard case .closed = phase else {
            phase = .closed
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

    private func register(
        waiterID: UUID,
        continuation: CheckedContinuation<Value, any Error>
    ) {
        if cancelledWaiters.remove(waiterID) != nil {
            continuation.resume(throwing: CancellationError())
            return
        }
        switch phase {
        case .ready(let value):
            continuation.resume(returning: value)
        case .failed(let error):
            continuation.resume(throwing: error)
        case .closed:
            continuation.resume(
                throwing: DIAsyncScopeError.closed(providerID: providerID)
            )
        case .idle, .running:
            waiters[waiterID] = continuation
            if case .idle = phase {
                startOwnedTask()
            }
        }
    }

    private func cancel(waiterID: UUID) {
        guard let waiter = waiters.removeValue(forKey: waiterID) else {
            if case .idle = phase {
                cancelledWaiters.insert(waiterID)
            } else if case .running = phase {
                cancelledWaiters.insert(waiterID)
            }
            return
        }
        waiter.resume(throwing: CancellationError())
    }

    private func startOwnedTask() {
        phase = .running
        let taskGeneration = generation
        let operation = operation
        let task = Task { try await operation() }
        ownedTask = task
        Task {
            do {
                finish(
                    generation: taskGeneration,
                    result: .success(try await task.value)
                )
            } catch {
                finish(
                    generation: taskGeneration,
                    result: .failure(error)
                )
            }
        }
    }

    private func finish(
        generation completedGeneration: Int,
        result: Result<Value, any Error>
    ) {
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
            phase = .failed(error)
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
