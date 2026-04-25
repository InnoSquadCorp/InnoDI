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
}
