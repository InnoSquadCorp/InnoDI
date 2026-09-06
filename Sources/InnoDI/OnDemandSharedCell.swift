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
        case initializing(owner: ObjectIdentifier)
        case ready(Value)
    }

    private let condition = NSCondition()
    private var state: State

    public init(factory: @escaping () -> Value) {
        state = .pending(factory)
    }

    public init(value: Value) {
        state = .ready(value)
    }

    public func value() -> Value {
        let caller = ObjectIdentifier(Thread.current)
        condition.lock()
        while true {
            switch state {
            case .ready(let value):
                condition.unlock()
                return value
            case .initializing(let owner):
                if owner == caller {
                    condition.unlock()
                    return _innoDITrap(
                        "Reentrant on-demand provider resolution detected"
                    )
                }
                condition.wait()
            case .pending(let factory):
                state = .initializing(owner: caller)
                condition.unlock()
                let value = factory()
                condition.lock()
                state = .ready(value)
                condition.broadcast()
                condition.unlock()
                return value
            }
        }
    }
}
