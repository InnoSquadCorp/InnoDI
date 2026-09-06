import Foundation

/// Compiler support for `@Provide(.shared, initialization: .onDemand)`.
///
/// Containers are value types, but their copies retain this reference cell so
/// they observe one logical shared instance. Independently initialized
/// containers receive independent cells. The factory runs outside the lock;
/// concurrent readers wait for the same result and same-thread re-entry traps
/// immediately instead of deadlocking forever.
@_documentation(visibility: internal)
public final class _InnoDISharedCell<Value>: @unchecked Sendable {
    private enum State {
        case pending(() -> Value)
        case initializing(owner: ObjectIdentifier, span: _InnoDITraceOwner.Span?)
        case ready(Value, span: _InnoDITraceOwner.Span?)
    }

    private let condition = NSCondition()
    private let traceOwner: _InnoDITraceOwner
    private let providerName: String
    private var state: State

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
                traceOwner.wait(.waitStart, member: providerName, for: span)
                condition.wait()
                traceOwner.wait(.waitEnd, member: providerName, for: span)
            case .pending(let factory):
                let span = traceOwner.start(member: providerName)
                state = .initializing(owner: caller, span: span)
                condition.unlock()
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
