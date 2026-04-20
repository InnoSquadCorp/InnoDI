import Testing

import InnoDI

// Deliberately collides with InnoDI's Provider<T> to prove the macro-generated
// wrappers preserve `InnoDI.Provider` when the user spells it that way.
struct Provider<T> {}

// MARK: - Fixtures
//
// The canonical Provider<T> use case: a `.shared` service (RequestLogger)
// wants to pump fresh `.transient` instances of another dependency (Request)
// on demand. If we injected the transient directly, the logger would capture
// one frozen instance at construction — defeating the whole point of
// `.transient`. Provider<T> gives the logger a handle that re-enters the
// container's transient accessor every time it's called.

final class Request {
    let config: Config
    init(config: Config) { self.config = config }
}

struct Config: Equatable {
    let endpoint: String
}

final class RequestLogger {
    let requests: InnoDI.Provider<Request>
    init(requests: InnoDI.Provider<Request>) { self.requests = requests }
    func makeRequest() -> Request { requests() }
}

@DIContainer
struct ProviderContainer {
    @Provide(.input)
    var config: Config

    @Provide(.transient, factory: { (config: Config) in
        Request(config: config)
    }, concrete: true)
    var request: Request

    @Provide(.shared, factory: { (request: InnoDI.Provider<Request>) in
        RequestLogger(requests: request)
    }, concrete: true)
    var logger: RequestLogger
}

// A second fixture where the transient accessor itself consumes a Provider
// parameter — proves transient-in-transient Provider wiring generates the
// `Provider({ self.<name> })` wrapper correctly.

struct PayloadInput: Equatable {
    let value: Int
}

final class Payload {
    let input: PayloadInput
    init(input: PayloadInput) { self.input = input }
}

final class PayloadProcessor {
    let payloads: InnoDI.Provider<Payload>
    init(payloads: InnoDI.Provider<Payload>) { self.payloads = payloads }
    func next() -> Payload { payloads() }
}

@DIContainer
struct TransientProviderContainer {
    @Provide(.input)
    var input: PayloadInput

    @Provide(.transient, factory: { (input: PayloadInput) in
        Payload(input: input)
    }, concrete: true)
    var payload: Payload

    @Provide(.transient, factory: { (payload: InnoDI.Provider<Payload>) in
        PayloadProcessor(payloads: payload)
    }, concrete: true)
    var processor: PayloadProcessor
}

@Suite("Provider runtime")
struct ProviderRuntimeTests {
    @Test("`.shared` factory sees a Provider that pumps fresh transient instances")
    func sharedFactoryReceivesProviderPumpingTransients() {
        let container = ProviderContainer(config: Config(endpoint: "https://a"))
        let logger = container.logger

        let first = logger.makeRequest()
        let second = logger.makeRequest()

        // Same endpoint (config propagates), but each invocation produced a
        // distinct Request object — the Provider didn't cache anything.
        #expect(first.config == Config(endpoint: "https://a"))
        #expect(second.config == Config(endpoint: "https://a"))
        #expect(first !== second)
    }

    @Test("Shared provider returns the same logger on repeated accessor calls")
    func sharedLoggerIdentityStable() {
        let container = ProviderContainer(config: Config(endpoint: "https://b"))

        let first = container.logger
        let second = container.logger

        // `logger` itself is `.shared` — only the Requests it pumps are fresh.
        #expect(first === second)
    }

    @Test("`.transient` factory can consume a Provider of another transient")
    func transientFactoryConsumesProvider() {
        let container = TransientProviderContainer(input: PayloadInput(value: 7))

        let processor = container.processor
        let p1 = processor.next()
        let p2 = processor.next()

        #expect(p1.input == PayloadInput(value: 7))
        #expect(p1 !== p2)
    }

    @Test("Each `.transient` accessor call produces an independent processor with an independent Provider closure")
    func transientProcessorsAreIndependent() {
        let container = TransientProviderContainer(input: PayloadInput(value: 1))

        let firstProcessor = container.processor
        let secondProcessor = container.processor

        // Fresh processor per accessor call — `.transient` semantics.
        #expect(firstProcessor !== secondProcessor)
        // But both processors still see payloads whose `.input` reflects the
        // container's input value.
        #expect(firstProcessor.next().input == PayloadInput(value: 1))
        #expect(secondProcessor.next().input == PayloadInput(value: 1))
    }
}
