import Dispatch
import Foundation

#if canImport(os)
import os

// Stable-address, nonrecursive locking is available at every supported Apple
// deployment target. All acquisition/release pairs below are synchronous.
private typealias DITraceLock = OSAllocatedUnfairLock<Void>
#else
private typealias DITraceLock = NSLock
#endif

/// A metadata-only dependency-resolution event. Input values, error payloads,
/// tokens, and service descriptions are intentionally absent from this type.
public struct DITraceEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case start
        case success
        case failure
        case cancel
        case cacheHit
        case override
        case waitStart
        case waitEnd
    }

    public enum Origin: String, Codable, Sendable {
        case factory
        case containerOverride
        case cache
        case wait
    }

    public let providerID: String
    public let ownerID: UUID
    public let generation: UInt64
    public let instanceID: UUID
    public let kind: Kind
    public let origin: Origin?
    public let relatedProviderID: String?
    public let relatedInstanceID: UUID?
    public let uptimeNanoseconds: UInt64

    public init(
        providerID: String,
        instanceID: UUID,
        kind: Kind,
        ownerID: UUID? = nil,
        generation: UInt64 = 0,
        origin: Origin? = nil,
        relatedProviderID: String? = nil,
        relatedInstanceID: UUID? = nil,
        uptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.providerID = providerID
        self.ownerID = ownerID ?? instanceID
        self.generation = generation
        self.instanceID = instanceID
        self.kind = kind
        self.origin = origin
        self.relatedProviderID = relatedProviderID
        self.relatedInstanceID = relatedInstanceID
        self.uptimeNanoseconds = uptimeNanoseconds
    }
}

/// Synchronous trace destination. Implementations must return quickly; InnoDI
/// never blocks provider construction on asynchronous logging or upload work.
public protocol DITraceSink: Sendable {
    func record(_ event: DITraceEvent)
}

/// Opt-in trace context. ``disabled`` stores no sink, allocates no buffer, and
/// does not evaluate event autoclosures.
public struct DITraceContext: Sendable {
    public static let disabled = Self(sink: nil)

    private let sink: (any DITraceSink)?
    private let targetIDsByModule: [String: String]
    private let generation: UInt64

    public init(
        sink: any DITraceSink,
        targetIDsByModule: [String: String] = [:],
        generation: UInt64 = 0
    ) {
        self.sink = sink
        self.targetIDsByModule = targetIDsByModule
        self.generation = generation
    }

    private init(sink: (any DITraceSink)?) {
        self.sink = sink
        targetIDsByModule = [:]
        generation = 0
    }

    public var isEnabled: Bool { sink != nil }

    /// Records a lazily constructed event only when tracing is enabled.
    public func emit(_ event: @autoclosure () -> DITraceEvent) {
        guard let sink else { return }
        sink.record(event())
    }

    /// Allocates a runtime instance ID and emits its start event. Returns nil
    /// on the disabled path, avoiding both UUID and event allocation.
    public func start(providerID: String) -> UUID? {
        guard sink != nil else { return nil }
        let instanceID = UUID()
        emit(
            DITraceEvent(
                providerID: providerID,
                instanceID: instanceID,
                kind: .start,
                generation: generation,
                origin: .factory
            )
        )
        return instanceID
    }

    /// Emits a terminal/cache/override event for a previously started runtime
    /// instance. A nil ID is the disabled-path token and is ignored.
    public func record(
        _ kind: DITraceEvent.Kind,
        providerID: String,
        instanceID: UUID?
    ) {
        guard let instanceID else { return }
        let origin: DITraceEvent.Origin? = switch kind {
        case .start, .success, .failure, .cancel:
            .factory
        case .cacheHit:
            .cache
        case .override:
            .containerOverride
        case .waitStart, .waitEnd:
            .wait
        }
        emit(
            DITraceEvent(
                providerID: providerID,
                instanceID: instanceID,
                kind: kind,
                generation: generation,
                origin: origin
            )
        )
    }

    /// Runs one synchronous provider resolution and records its terminal
    /// outcome. The disabled path calls `operation` directly without creating
    /// an instance identifier or event.
    public func withResolution<Value>(
        providerID: String,
        _ operation: () throws -> Value
    ) rethrows -> Value {
        guard isEnabled else { return try operation() }
        let instanceID = start(providerID: providerID)
        do {
            let value = try operation()
            record(.success, providerID: providerID, instanceID: instanceID)
            return value
        } catch let cancellation as CancellationError {
            record(.cancel, providerID: providerID, instanceID: instanceID)
            throw cancellation
        } catch {
            record(.failure, providerID: providerID, instanceID: instanceID)
            throw error
        }
    }

    /// Runs one asynchronous provider resolution and records success, failure,
    /// or cooperative cancellation without serializing an error or result.
    public nonisolated(nonsending) func withResolution<Value>(
        providerID: String,
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        guard isEnabled else { return try await operation() }
        let instanceID = start(providerID: providerID)
        do {
            let value = try await operation()
            record(.success, providerID: providerID, instanceID: instanceID)
            return value
        } catch let cancellation as CancellationError {
            record(.cancel, providerID: providerID, instanceID: instanceID)
            throw cancellation
        } catch {
            record(.failure, providerID: providerID, instanceID: instanceID)
            throw error
        }
    }

    fileprivate func targetID(for moduleName: String) -> String? {
        targetIDsByModule[moduleName]
    }

    fileprivate var traceGeneration: UInt64 { generation }

    fileprivate func record(_ event: DITraceEvent) {
        emit(event)
    }
}

/// Compiler support retained by generated containers so later provider reads
/// remain correlated with the container instance that created them.
@_documentation(visibility: internal)
public struct _InnoDITraceOwner: Sendable {
    public struct Span: Sendable {
        fileprivate let providerID: String
        fileprivate let instanceID: UUID
    }

    private final class State: @unchecked Sendable {
        let ownerID = UUID()
        private let lock = DITraceLock()
        private var latestSpans: [String: Span] = [:]

        func start(member: String, containerID: String, instanceID: UUID) -> Span {
            lock.lock()
            defer { lock.unlock() }
            // The provider's semantic ID is immutable for this owner. Reuse
            // that string, not the span identity: every resolution still gets
            // its own UUID and replaces the latest span under the same lock.
            let providerID = latestSpans[member]?.providerID ?? "\(containerID).\(member)"
            let span = Span(providerID: providerID, instanceID: instanceID)
            latestSpans[member] = span
            return span
        }

        func span(member: String) -> Span? {
            lock.lock()
            defer { lock.unlock() }
            return latestSpans[member]
        }
    }

    private let context: DITraceContext
    private let state: State?
    private let generation: UInt64
    private let containerID: String

    public init(context: DITraceContext, containerType: Any.Type) {
        self.context = context
        generation = context.traceGeneration

        guard context.isEnabled else {
            state = nil
            containerID = ""
            return
        }

        state = State()
        let reflected = String(reflecting: containerType)
        let components = reflected.split(separator: ".", omittingEmptySubsequences: true)
        let moduleName = components.first.map(String.init) ?? reflected
        let semanticPath = components
            .dropFirst()
            .filter { !$0.hasPrefix("(unknown context at $") }
            .joined(separator: ".")
        if let targetID = context.targetID(for: moduleName), !semanticPath.isEmpty {
            containerID = "\(targetID)::\(semanticPath)"
        } else {
            containerID = reflected
        }
    }

    public static let disabled = Self(
        context: .disabled,
        containerType: Never.self
    )

    public var isEnabled: Bool { state != nil }

    public func providerID(member: String) -> String? {
        guard state != nil else { return nil }
        return "\(containerID).\(member)"
    }

    public func start(member: String) -> Span? {
        guard let state else { return nil }
        let instanceID = UUID()
        let span = state.start(member: member, containerID: containerID, instanceID: instanceID)
        context.record(
            DITraceEvent(
                providerID: span.providerID,
                instanceID: instanceID,
                kind: .start,
                ownerID: state.ownerID,
                generation: generation,
                origin: .factory
            )
        )
        return span
    }

    public func finish(_ kind: DITraceEvent.Kind, span: Span?) {
        guard let state, let span else { return }
        context.record(
            DITraceEvent(
                providerID: span.providerID,
                instanceID: span.instanceID,
                kind: kind,
                ownerID: state.ownerID,
                generation: generation,
                origin: kind == .override ? .containerOverride : .factory
            )
        )
    }

    public func withResolution<Value>(
        member: String,
        _ operation: () throws -> Value
    ) rethrows -> Value {
        guard isEnabled else { return try operation() }
        return try withResolution(span: start(member: member), operation)
    }

    public func withResolution<Value>(
        span: Span?,
        _ operation: () throws -> Value
    ) rethrows -> Value {
        guard isEnabled else { return try operation() }
        do {
            let value = try operation()
            finish(.success, span: span)
            return value
        } catch let cancellation as CancellationError {
            finish(.cancel, span: span)
            throw cancellation
        } catch {
            finish(.failure, span: span)
            throw error
        }
    }

    public nonisolated(nonsending) func withResolution<Value>(
        member: String,
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        guard isEnabled else { return try await operation() }
        return try await withResolution(
            span: start(member: member),
            operation
        )
    }

    public nonisolated(nonsending) func withResolution<Value>(
        span: Span?,
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        guard isEnabled else { return try await operation() }
        do {
            let value = try await operation()
            finish(.success, span: span)
            return value
        } catch let cancellation as CancellationError {
            finish(.cancel, span: span)
            throw cancellation
        } catch {
            finish(.failure, span: span)
            throw error
        }
    }

    public func overridden<Value>(member: String, value: Value) -> Value {
        guard isEnabled else { return value }
        return overridden(
            member: member,
            value: value,
            span: start(member: member)
        )
    }

    public func overridden<Value>(
        member: String,
        value: Value,
        span: Span?
    ) -> Value {
        guard isEnabled else { return value }
        finish(.override, span: span)
        return value
    }

    public func cacheHit(member: String, span explicitSpan: Span? = nil) {
        guard let state,
              let span = explicitSpan ?? state.span(member: member) else {
            return
        }
        context.record(
            DITraceEvent(
                providerID: span.providerID,
                instanceID: span.instanceID,
                kind: .cacheHit,
                ownerID: state.ownerID,
                generation: generation,
                origin: .cache
            )
        )
    }

    public func wait(_ kind: DITraceEvent.Kind, member: String, for span: Span?) {
        guard let state,
              let span,
              kind == .waitStart || kind == .waitEnd,
              let providerID = providerID(member: member) else {
            return
        }
        context.record(
            DITraceEvent(
                providerID: providerID,
                instanceID: span.instanceID,
                kind: kind,
                ownerID: state.ownerID,
                generation: generation,
                origin: .wait,
                relatedProviderID: span.providerID,
                relatedInstanceID: span.instanceID
            )
        )
    }

    public nonisolated(nonsending) func withWait<Value>(
        member: String,
        forMember dependencyMember: String,
        _ operation: () async throws -> Value
    ) async rethrows -> Value {
        guard let state,
              let current = state.span(member: member),
              let dependency = state.span(member: dependencyMember) else {
            return try await operation()
        }
        context.record(
            DITraceEvent(
                providerID: current.providerID,
                instanceID: current.instanceID,
                kind: .waitStart,
                ownerID: state.ownerID,
                generation: generation,
                origin: .wait,
                relatedProviderID: dependency.providerID,
                relatedInstanceID: dependency.instanceID
            )
        )
        defer {
            context.record(
                DITraceEvent(
                    providerID: current.providerID,
                    instanceID: current.instanceID,
                    kind: .waitEnd,
                    ownerID: state.ownerID,
                    generation: generation,
                    origin: .wait,
                    relatedProviderID: dependency.providerID,
                    relatedInstanceID: dependency.instanceID
                )
            )
        }
        return try await operation()
    }
}

/// A lock-safe bounded in-memory trace sink. When full it drops the oldest
/// event and increments ``Snapshot/droppedEventCount``.
public final class DIBoundedTraceBuffer: DITraceSink, @unchecked Sendable {
    public struct Snapshot: Sendable {
        public let events: [DITraceEvent]
        public let droppedEventCount: Int
    }

    private let capacity: Int
    private let lock = DITraceLock()
    private var storage: [DITraceEvent]
    private var startIndex = 0
    private var droppedEventCount = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "DIBoundedTraceBuffer capacity must be positive")
        self.capacity = capacity
        storage = []
        storage.reserveCapacity(capacity)
    }

    public func record(_ event: DITraceEvent) {
        lock.lock()
        defer { lock.unlock() }
        if storage.count == capacity {
            storage[startIndex] = event
            startIndex += 1
            if startIndex == capacity { startIndex = 0 }
            droppedEventCount += 1
            return
        }
        storage.append(event)
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        var events: [DITraceEvent] = []
        events.reserveCapacity(storage.count)
        // Only initialized events occupy the ring. Copy its two contiguous
        // segments in bulk instead of unwrapping and appending every slot
        // while all writers are waiting for this lock.
        events.append(contentsOf: storage[startIndex...])
        events.append(contentsOf: storage[..<startIndex])
        return Snapshot(events: events, droppedEventCount: droppedEventCount)
    }
}
