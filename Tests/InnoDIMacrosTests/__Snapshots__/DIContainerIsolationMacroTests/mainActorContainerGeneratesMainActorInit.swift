
struct AppContainer {
    @_Concurrency.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config

    // MARK: - Initialization
    @_Concurrency.MainActor init(config: Config) {
        self._storage_config = config
    }

    // MARK: - Overrides Builder
    @_Concurrency.MainActor struct Overrides {
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @_Concurrency.MainActor init(config: Config, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config)
    }

    // MARK: - withOverrides
    @_Concurrency.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @_Concurrency.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @_Concurrency.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @_Concurrency.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}