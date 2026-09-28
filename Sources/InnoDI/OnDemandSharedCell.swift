import Foundation

/// Compiler support for `@Provide(.shared, initialization: .onDemand)`.
///
/// Containers are value types, but their copies retain this reference cell so
/// they observe one logical shared instance. Independently initialized
/// containers receive independent cells. The factory runs outside the lock;
/// concurrent readers wait for the same result and same-thread re-entry traps
/// immediately instead of deadlocking forever.
///
/// This deferred handle is intentionally non-Sendable. The lock protects
/// initialization, not the payload or arbitrary values captured by its factory.
/// Keep it on the container's isolation domain, just like `Lazy` and `Provider`.
@_documentation(visibility: internal)
public final class _InnoDISharedCell<Value> {
    private enum State {
        case pending(() -> Value)
        case initializing(owner: ObjectIdentifier, span: _InnoDITraceOwner.Span?)
        case ready(Value, span: _InnoDITraceOwner.Span?)
    }

    private let condition = NSCondition()
    private let traceOwner: _InnoDITraceOwner
    private let providerName: String
    private var state: State
    private var activeCallers: Set<ObjectIdentifier> = []

    public init(factory: @escaping () -> Value) {
        traceOwner = .disabled
        providerName = ""
        state = .pending(factory)
    }

    public init(value: Value) {
        traceOwner = .disabled
        providerName = ""
        state = .ready(value, span: nil)
    }

    public init(
        traceOwner: _InnoDITraceOwner,
        providerName: String,
        factory: @escaping () -> Value
    ) {
        self.traceOwner = traceOwner
        self.providerName = providerName
        state = .pending(factory)
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
        state = .ready(value, span: span)
    }

    public func value() -> Value {
        let caller = ObjectIdentifier(Thread.current)
        condition.lock()
        guard activeCallers.insert(caller).inserted else {
            condition.unlock()
            return _innoDITrap("Reentrant on-demand provider resolution detected")
        }
        defer {
            condition.lock()
            activeCallers.remove(caller)
            condition.unlock()
        }
        while true {
            switch state {
            case .ready(let value, let span):
                condition.unlock()
                traceOwner.cacheHit(member: providerName, span: span)
                return value
            case .initializing(let owner, let span):
                if owner == caller {
                    condition.unlock()
                    return _innoDITrap(
                        "Reentrant on-demand provider resolution detected"
                    )
                }
                condition.unlock()
                traceOwner.wait(.waitStart, member: providerName, for: span)
                condition.lock()
                // The factory can finish while a sink runs. Recheck under the
                // lock before sleeping so its broadcast cannot be lost.
                while case .initializing = state { condition.wait() }
                condition.unlock()
                traceOwner.wait(.waitEnd, member: providerName, for: span)
                condition.lock()
            case .pending(let factory):
                let span = traceOwner.prepareSpan(member: providerName)
                state = .initializing(owner: caller, span: span)
                condition.unlock()
                traceOwner.emitStart(span: span)
                let value = factory()
                condition.lock()
                state = .ready(value, span: span)
                condition.broadcast()
                condition.unlock()
                traceOwner.finish(.success, span: span)
                return value
            }
        }
    }
}

/// Compiler support for an on-demand dependency captured by an async factory.
///
/// Unlike the unrestricted deferred cell, construction checks both the payload
/// and every factory capture. Its private initialization state is lock-protected;
/// the exposed isolated view cannot replace its factory or payload. No conversion
/// from an already-created, unrestricted cell is provided.
@_documentation(visibility: internal)
public struct _InnoDISendableSharedCell<Value: Sendable>: @unchecked Sendable {
    public let isolated: _InnoDISharedCell<Value>

    public init(
        traceOwner: _InnoDITraceOwner,
        providerName: String,
        factory: @escaping @Sendable () -> Value
    ) {
        isolated = _InnoDISharedCell(
            traceOwner: traceOwner, providerName: providerName, factory: factory
        )
    }

    public init(traceOwner: _InnoDITraceOwner, providerName: String, value: Value) {
        isolated = _InnoDISharedCell(
            traceOwner: traceOwner, providerName: providerName, value: value
        )
    }

    public func value() -> Value { isolated.value() }
}
