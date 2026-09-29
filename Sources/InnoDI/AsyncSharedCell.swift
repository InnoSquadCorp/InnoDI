import Foundation
import os

/// Compiler support for
/// `@Provide(.shared, initialization: .onDemand, asyncFactory:)`.
///
/// Container copies retain this reference so they observe one logical
/// provider. Independently initialized containers receive independent cells.
/// The first read starts one construction task owned by a ``DIAsyncScope``.
/// Concurrent readers wait for that task, and cancelling a reader cancels
/// only its own wait. A completed value or failure is cached for the lifetime
/// of the cell, like an eager asynchronous `.shared` provider.
///
/// ``close()`` cancels in-flight construction, resumes every waiting reader
/// with ``DIAsyncScopeError/closed(providerID:)``, and releases the factory's
/// captures. Later reads throw the same error, including for an overridden
/// value, so tests that override the provider observe the production close
/// contract. The provider ID in that error is the provider's member name.
///
/// The payload and every factory capture are checked as `Sendable` through
/// the `@Sendable` operation, so the cell itself is `Sendable` without an
/// unchecked conformance.
@_documentation(visibility: internal)
public final class _InnoDIAsyncSharedCell<Value: Sendable>: Sendable {
    private enum Source: Sendable {
        case scope(DIAsyncScope<Value>)
        case value(Value)
    }

    /// Trace bookkeeping plus the closed flag for overridden values. The
    /// owned scope remains the source of truth for values, failures, and
    /// waiters. `closed` is terminal.
    private enum Phase: Sendable {
        case idle
        case running(_InnoDITraceOwner.Span?)
        case completed(_InnoDITraceOwner.Span?)
        case closed
    }

    private let source: Source
    private let traceOwner: _InnoDITraceOwner
    private let providerName: String
    private let phase: OSAllocatedUnfairLock<Phase>

    public init(
        traceOwner: _InnoDITraceOwner,
        providerName: String,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        let phase = OSAllocatedUnfairLock<Phase>(initialState: .idle)
        self.phase = phase
        self.traceOwner = traceOwner
        self.providerName = providerName
        source = .scope(
            DIAsyncScope(providerID: providerName) {
                // The scope runs this operation at most once, on its owned
                // task, so construction start and outcome are traced once.
                let span = traceOwner.prepareSpan(member: providerName)
                Self.advance(phase, to: .running(span))
                traceOwner.emitStart(span: span)
                do {
                    let value = try await operation()
                    Self.advance(phase, to: .completed(span))
                    traceOwner.finish(.success, span: span)
                    return value
                } catch let cancellation as CancellationError {
                    Self.advance(phase, to: .completed(span))
                    traceOwner.finish(.cancel, span: span)
                    throw cancellation
                } catch {
                    Self.advance(phase, to: .completed(span))
                    traceOwner.finish(.failure, span: span)
                    throw error
                }
            }
        )
    }

    public init(
        traceOwner: _InnoDITraceOwner,
        providerName: String,
        value: Value
    ) {
        self.traceOwner = traceOwner
        self.providerName = providerName
        let span = traceOwner.start(member: providerName)
        traceOwner.finish(.override, span: span)
        phase = OSAllocatedUnfairLock(initialState: .completed(span))
        source = .value(value)
    }

    public func value() async throws -> Value {
        let currentPhase = phase.withLock { $0 }
        if case .closed = currentPhase {
            throw DIAsyncScopeError.closed(providerID: providerName)
        }

        let scope: DIAsyncScope<Value>
        switch source {
        case .value(let value):
            try Task.checkCancellation()
            if case .completed(let span) = currentPhase {
                traceOwner.cacheHit(member: providerName, span: span)
            }
            return value
        case .scope(let ownedScope):
            scope = ownedScope
        }

        switch currentPhase {
        case .closed:
            throw DIAsyncScopeError.closed(providerID: providerName)
        case .idle:
            // This read starts construction, or joins a construction whose
            // owned task has not reported its start yet.
            return try await scope.value()
        case .running(let span):
            traceOwner.wait(.waitStart, member: providerName, for: span)
            let result: Result<Value, any Error>
            do {
                result = .success(try await scope.value())
            } catch {
                result = .failure(error)
            }
            traceOwner.wait(.waitEnd, member: providerName, for: span)
            let value = try result.get()
            traceOwner.cacheHit(member: providerName, span: span)
            return value
        case .completed(let span):
            let value = try await scope.value()
            traceOwner.cacheHit(member: providerName, span: span)
            return value
        }
    }

    /// Cancels in-flight construction and permanently closes the provider.
    /// Closing is idempotent and also closes an overridden provider.
    public func close() async {
        phase.withLock { $0 = .closed }
        guard case .scope(let scope) = source else { return }
        await scope.close()
    }

    /// Records trace progress without reopening a closed provider.
    private static func advance(
        _ phase: OSAllocatedUnfairLock<Phase>,
        to next: Phase
    ) {
        phase.withLock { current in
            if case .closed = current { return }
            current = next
        }
    }
}
