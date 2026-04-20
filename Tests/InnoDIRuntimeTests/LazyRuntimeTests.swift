import Testing

import InnoDI

// MARK: - Fixtures
//
// ViewModel ↔ Coordinator is the canonical two-cycle: the coordinator needs
// the view model to drive transitions, and the view model needs the
// coordinator to request navigation. Without the Lazy escape hatch, one of
// these has to be mutated post-construction or restructured — InnoDI's
// cycle detector rejects the container outright.
//
// With `Lazy<T>`, we break the cycle by deferring the resolution of `b` on
// the `a` side: `a`'s factory stores the Lazy wrapper without invoking it,
// so `CoordinatorA` is constructed before `b` exists. Once init has written
// `_storage_b`, the `_lazyCell_b` box is populated and any later
// `a.resolveB()` returns the shared `.shared` instance.

final class CoordinatorA {
    private let _b: Lazy<CoordinatorB>
    init(b: Lazy<CoordinatorB>) { self._b = b }
    func resolveB() -> CoordinatorB { _b() }
}

final class CoordinatorB {
    let a: CoordinatorA
    init(a: CoordinatorA) { self.a = a }
}

@DIContainer
struct LazyCycleContainer {
    // Declare the soft-target side first. `a`'s factory receives the Lazy
    // wrapper and stores it — the wrapper resolves `b` only when invoked at
    // call time, by which point init has fully populated `_lazyCell_b`.
    @Provide(.shared, factory: { (b: Lazy<CoordinatorB>) in
        CoordinatorA(b: b)
    }, concrete: true)
    var a: CoordinatorA

    @Provide(.shared, factory: { (a: CoordinatorA) in
        CoordinatorB(a: a)
    }, concrete: true)
    var b: CoordinatorB
}

// MARK: - Tests

/// Runtime coverage for Phase K's `Lazy<T>` cycle escape hatch.
///
/// The macro's expansion is covered by snapshot tests under
/// `Tests/InnoDIMacrosTests/`. These tests assert that the generated init
/// actually *runs*: the `_LazyCell` box ends up populated, Lazy resolution
/// returns the shared `.shared` identity, and forward factory references
/// compile cleanly end-to-end.
@Suite("@DIContainer Lazy cycle escape")
struct LazyRuntimeTests {
    @Test("Two-shared cycle resolves through Lazy with preserved identity")
    func twoCycleResolvesViaLazy() {
        let container = LazyCycleContainer()

        let a = container.a
        let b = container.b

        // `b.a` is the eagerly-injected CoordinatorA.
        // `a.resolveB()` goes through the Lazy back to the same CoordinatorB
        // instance stored in `_storage_b`.
        #expect(b.a === a)
        #expect(a.resolveB() === b)

        // Repeated resolution returns the same shared `b` — Lazy does not
        // introduce its own caching, but `.shared` storage does.
        #expect(a.resolveB() === a.resolveB())
    }

    @Test("Accessor retrieves the same shared identity across calls")
    func sharedIdentityAcrossAccessorCalls() {
        let container = LazyCycleContainer()
        #expect(container.a === container.a)
        #expect(container.b === container.b)
    }
}
