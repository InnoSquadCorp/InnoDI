import Dispatch
import Foundation

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
    }

    public let providerID: String
    public let instanceID: UUID
    public let kind: Kind
    public let uptimeNanoseconds: UInt64

    public init(
        providerID: String,
        instanceID: UUID,
        kind: Kind,
        uptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.providerID = providerID
        self.instanceID = instanceID
        self.kind = kind
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

    public init(sink: any DITraceSink) {
        self.sink = sink
    }

    private init(sink: (any DITraceSink)?) {
        self.sink = sink
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
        emit(DITraceEvent(providerID: providerID, instanceID: instanceID, kind: .start))
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
        emit(DITraceEvent(providerID: providerID, instanceID: instanceID, kind: kind))
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
    public func withResolution<Value>(
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
}

/// A lock-safe bounded in-memory trace sink. When full it drops the oldest
/// event and increments ``Snapshot/droppedEventCount``.
public final class DIBoundedTraceBuffer: DITraceSink, @unchecked Sendable {
    public struct Snapshot: Sendable {
        public let events: [DITraceEvent]
        public let droppedEventCount: Int
    }

    private let capacity: Int
    private let lock = NSLock()
    private var events: [DITraceEvent] = []
    private var droppedEventCount = 0

    public init(capacity: Int) {
        precondition(capacity > 0, "DIBoundedTraceBuffer capacity must be positive")
        self.capacity = capacity
        events.reserveCapacity(capacity)
    }

    public func record(_ event: DITraceEvent) {
        lock.lock()
        defer { lock.unlock() }
        if events.count == capacity {
            events.removeFirst()
            droppedEventCount += 1
        }
        events.append(event)
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(events: events, droppedEventCount: droppedEventCount)
    }
}
