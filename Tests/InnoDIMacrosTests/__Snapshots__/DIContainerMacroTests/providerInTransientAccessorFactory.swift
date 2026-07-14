
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var input: PayloadInput

    private var _storage_input: PayloadInput? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var payload: Payload

    private var _override_payload: Payload? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var processor: PayloadProcessor

    private var _override_processor: PayloadProcessor? = nil

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
    static func withOverrides<OperationResult>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(input: input, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(input: input, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(input: input, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(input: PayloadInput, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(input: input, applyOverrides)
        return try await operation(container)
    }
}