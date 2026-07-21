
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var input: PayloadInput
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var payload: Payload
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var processor: PayloadProcessor

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

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    init(input: PayloadInput, _ _innoDIApplyOverrides: (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(input: input, payload: _innoDIOverrides.payload, processor: _innoDIOverrides.processor)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(input: PayloadInput, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(input: input, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(input: PayloadInput, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(input: input, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(input: PayloadInput, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(input: input, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(input: PayloadInput, _ _innoDIApplyOverrides: (inout Overrides) -> Void, operation _innoDIOperation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(input: input, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}