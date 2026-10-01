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
/// with ``DIAsyncScopeError/closed(providerID:)``, and releases the value.
/// A construction task that has not begun yet never starts the factory. A
/// factory that is already running observes cancellation, and a result it
/// returns anyway is discarded and traced as a cancellation. Later reads throw
/// the same error, and closing an overridden value releases it too, so tests
/// that override the provider observe the production close contract. The
/// provider ID in that error is the provider's member name.
///
/// The payload and every factory capture are checked as `Sendable` through
/// the `@Sendable` operation, so the cell itself is `Sendable` without an
/// unchecked conformance.
@_documentation(visibility: internal)
public final class _InnoDIAsyncSharedCell<Value: Sendable>: Sendable {
    private enum Source: Sendable {
        case scope(DIAsyncScope<Value>)
        case override
    }

    /// Trace bookkeeping plus the closed flag. The owned scope remains the
    /// source of truth for constructed values, failures, and waiters.
    /// `closed` is terminal.
    private enum Phase: Sendable {
        case idle
        case running(_InnoDITraceOwner.Span?)
        case completed(_InnoDITraceOwner.Span?)
        case closed
    }

    private struct State: Sendable {
        var phase: Phase
        /// An overridden value, until ``close()`` releases it.
        var overrideValue: Value?
    }

    private let source: Source
    private let traceOwner: _InnoDITraceOwner
    private let providerName: String
    private let state: OSAllocatedUnfairLock<State>

    public init(
        traceOwner: _InnoDITraceOwner,
        providerName: String,
        operation: @escaping @Sendable () async throws -> Value
    ) {
        let state = OSAllocatedUnfairLock(initialState: State(phase: .idle, overrideValue: nil))
        self.state = state
        self.traceOwner = traceOwner
        self.providerName = providerName
        source = .scope(
            DIAsyncScope(providerID: providerName) {
                // `close()` closes this cell before it cancels the owned
                // task, and the task can begin running after either step. A
                // closed cell never starts the factory.
                try Task.checkCancellation()
                if Self.isClosed(state) {
                    throw DIAsyncScopeError.closed(providerID: providerName)
                }
                // The scope runs this operation at most once, on its owned
                // task, so construction start and outcome are traced once.
                let span = traceOwner.prepareSpan(member: providerName)
                Self.advance(state, to: .running(span))
                traceOwner.emitStart(span: span)
                let outcome: Result<Value, any Error>
                do {
                    outcome = .success(try await operation())
                } catch {
                    outcome = .failure(error)
                }
                // Read before `advance`, which leaves a closed phase alone.
                if Self.isClosed(state) {
                    // The close discards the outcome. The scope may not be
                    // closed yet, so waiters must see the close rather than a
                    // cancellation or the factory's own result.
                    traceOwner.finish(.cancel, span: span)
                    throw DIAsyncScopeError.closed(providerID: providerName)
                }
                Self.advance(state, to: .completed(span))
                switch outcome {
                case .success(let value):
                    traceOwner.finish(.success, span: span)
                    return value
                case .failure(let cancellation as CancellationError):
                    traceOwner.finish(.cancel, span: span)
                    throw cancellation
                case .failure(let error):
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
        state = OSAllocatedUnfairLock(
            initialState: State(phase: .completed(span), overrideValue: value)
        )
        source = .override
    }

    public func value() async throws -> Value {
        let current = state.withLock { $0 }
        let currentPhase = current.phase
        if case .closed = currentPhase {
            throw DIAsyncScopeError.closed(providerID: providerName)
        }

        let scope: DIAsyncScope<Value>
        switch source {
        case .override:
            try Task.checkCancellation()
            guard let value = current.overrideValue else {
                throw DIAsyncScopeError.closed(providerID: providerName)
            }
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
        // The released value goes out of scope after the lock is dropped, so
        // its deinitializer never runs while the lock is held.
        _ = state.withLock { current -> Value? in
            current.phase = .closed
            let released = current.overrideValue
            current.overrideValue = nil
            return released
        }
        guard case .scope(let scope) = source else { return }
        await scope.close()
    }

    /// Records trace progress without reopening a closed provider.
    private static func advance(
        _ state: OSAllocatedUnfairLock<State>,
        to next: Phase
    ) {
        state.withLock { current in
            if case .closed = current.phase { return }
            current.phase = next
        }
    }

    private static func isClosed(_ state: OSAllocatedUnfairLock<State>) -> Bool {
        state.withLock { current in
            if case .closed = current.phase { return true }
            return false
        }
    }
}
