import Testing

import InnoDI

private struct SendablePayload: Sendable, Equatable {
    let value: Int
}

@Suite("Strict concurrency runtime surface")
struct StrictConcurrencyRuntimeTests {
    @Test("Lazy and Provider still resolve sendable payloads without sendability guarantees")
    func deferredWrappersResolveSendablePayloads() {
        let lazy = InnoDI.Lazy<SendablePayload> { SendablePayload(value: 1) }
        let provider = InnoDI.Provider<SendablePayload> { SendablePayload(value: 2) }

        #expect(lazy().value == 1)
        #expect(provider().value == 2)
    }

    @Test("_LazyCell stores concrete values for later deferred resolution")
    func lazyCellStoresConcreteValues() {
        let cell = _LazyCell<SendablePayload>()
        cell.storeValue(SendablePayload(value: 42))

        #expect(cell.resolve() == SendablePayload(value: 42))
    }

    @Test("_LazyCell binds deferred resolvers without exposing raw mutable state")
    func lazyCellBindsDeferredResolvers() {
        let cell = _LazyCell<SendablePayload>()
        var nextValue = 0

        cell.bindResolver {
            nextValue += 1
            return SendablePayload(value: nextValue)
        }

        #expect(cell.resolve() == SendablePayload(value: 1))
        #expect(cell.resolve() == SendablePayload(value: 2))
    }
}
