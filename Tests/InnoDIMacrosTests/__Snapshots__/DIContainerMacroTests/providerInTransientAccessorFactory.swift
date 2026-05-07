
struct AppContainer {
    var input: PayloadInput {
        get {
            return _storage_input
        }
    }

    private let _storage_input: PayloadInput
    var payload: Payload {
        get {
            if let override = _override_payload {
                return override
            }
            return { (input: PayloadInput) in
                    Payload(input: input)
                }(self.input)
        }
    }

    private let _override_payload: Payload?
    var processor: PayloadProcessor {
        get {
            if let override = _override_processor {
                return override
            }
            return { (payload: Provider<Payload>) in
                    PayloadProcessor(payloads: payload)
                }(Provider {
                    self.payload
                })
        }
    }

    private let _override_processor: PayloadProcessor?

    // MARK: - Initialization
    init(input: PayloadInput, payload: Payload? = nil, processor: PayloadProcessor? = nil) {
        self._storage_input = input
        self._override_payload = payload
        self._override_processor = processor
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var payload: Payload? = nil
        var processor: PayloadProcessor? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(input: input, payload: overrides.payload, processor: overrides.processor)
    }

    // MARK: - withOverrides
    static func withOverrides<T>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(input: input, applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(input: input, applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(input: input, applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(input: input, applyOverrides)
        return try await operation(container)
    }
}