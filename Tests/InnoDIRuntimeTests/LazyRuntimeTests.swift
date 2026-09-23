import Testing

import InnoDI

// Deliberately collides with InnoDI's Lazy<T> to prove the macro-generated
// wrappers preserve `InnoDI.Lazy` when the user spells it that way.
struct Lazy<T> {
    init() {}
}

// MARK: - Fixtures
//
// Deferred forward references remain supported in acyclic graphs. Cycles
// are compile-fail fixtures, not runtime fixtures that intentionally leak.

final class CoordinatorA {
    private let _b: InnoDI.Lazy<CoordinatorB>
    init(b: InnoDI.Lazy<CoordinatorB>) { self._b = b }
    func resolveB() -> CoordinatorB { _b() }
}

final class CoordinatorB {}

@DIContainer
struct LazyAcyclicContainer {
    // Declare the soft-target side first. `a`'s factory receives the Lazy
    // wrapper and stores it — the wrapper resolves `b` only when invoked at
    // call time, by which point init has fully populated `_innoDILazyCell_b`.
    @Provide(.shared, factory: { (b: InnoDI.Lazy<CoordinatorB>) in
        CoordinatorA(b: b)
    })
    var a: CoordinatorA

    @Provide(.shared, factory: CoordinatorB())
    var b: CoordinatorB
}

final class TransientService {}

final class TransientHolder {
    private let _service: InnoDI.Lazy<TransientService>

    init(service: InnoDI.Lazy<TransientService>) {
        _service = service
    }

    func resolveService() -> TransientService {
        _service()
    }
}

@DIContainer
struct LazyTransientContainer {
    @Provide(.shared, factory: { (service: InnoDI.Lazy<TransientService>) in
        TransientHolder(service: service)
    })
    var holder: TransientHolder

    @Provide(.transient, factory: { TransientService() })
    var service: TransientService
}

// MARK: - Tests

/// Runtime coverage for acyclic `Lazy<T>` ownership.
///
/// The macro's expansion is covered by snapshot tests under
/// `Tests/InnoDIMacrosTests/`. These tests assert that the generated init
/// actually *runs*: deferred cell wiring is populated, Lazy resolution returns
/// the shared `.shared` identity, and forward factory references compile
/// cleanly end-to-end.
@Suite("@DIContainer Lazy acyclic ownership")
struct LazyRuntimeTests {
    @Test("Deferred forward reference preserves shared identity")
    func forwardReferenceResolvesViaLazy() {
        let container = LazyAcyclicContainer()

        let a = container.a
        let b = container.b

        #expect(a.resolveB() === b)

        // Repeated resolution returns the same shared `b` — Lazy does not
        // introduce its own caching, but `.shared` storage does.
        #expect(a.resolveB() === a.resolveB())
    }

    @Test("Accessor retrieves the same shared identity across calls")
    func sharedIdentityAcrossAccessorCalls() {
        let container = LazyAcyclicContainer()
        #expect(container.a === container.a)
        #expect(container.b === container.b)
    }

    @Test("Copied containers and escaped lazy owners release the last context")
    func escapedLazyOwnerLifetime() {
        var container: LazyAcyclicContainer? = LazyAcyclicContainer()
        var copy = container
        var escapedOwner = container?.a
        weak var weakOwner = container?.a
        weak var weakTarget = container?.b
        container = nil
        #expect(copy?.a === escapedOwner)
        copy = nil
        #expect(escapedOwner?.resolveB() === weakTarget)
        #expect(weakOwner != nil)
        escapedOwner = nil
        #expect(weakOwner == nil)
        #expect(weakTarget == nil)
        weakOwner = nil
        weakTarget = nil
    }

    @Test("Uncalled lazy resolver context is released with the last container")
    func uncalledLazyContextIsReleased() {
        var container: LazyAcyclicContainer? = LazyAcyclicContainer()
        weak var weakOwner = container?.a
        weak var weakTarget = container?.b
        container = nil
        #expect(weakOwner == nil)
        #expect(weakTarget == nil)
        weakOwner = nil
        weakTarget = nil
    }

    @Test("Shared -> Lazy<Transient> resolves a fresh transient instance per call")
    func transientTargetResolvesFreshInstancePerCall() {
        let container = LazyTransientContainer()
        let first = container.holder.resolveService()
        let second = container.holder.resolveService()
        #expect(first !== second)
    }

    @Test("Shared -> Lazy<Transient> uses the direct override path when supplied")
    func transientTargetUsesOverrideWhenProvided() {
        let override = TransientService()
        let container = LazyTransientContainer(service: override)
        #expect(container.holder.resolveService() === override)
        #expect(container.holder.resolveService() === override)
    }
}
