
struct AppContainer {
    @Swift.MainActor @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config

    // MARK: - Initialization
    @Swift.MainActor init(config: Config) {
        self._storage_config = config
    }

    // MARK: - Overrides Builder
    @Swift.MainActor struct Overrides {
    }

    typealias _InnoDIMountOverrides = Overrides

    // MARK: - Convenience Init with Overrides
    @Swift.MainActor init(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void) {
        var _innoDIOverrides = Self.Overrides()
        _innoDIApplyOverrides(&_innoDIOverrides)
        self.init(config: config)
    }

    // MARK: - withOverrides
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) -> OperationResult) -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (throws)
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async)
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async -> OperationResult) async -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return await _innoDIOperation(_innoDIContainer)
    }

    // MARK: - withOverrides (async throws)
    @Swift.MainActor static func withOverrides<OperationResult>(config: Config, _ _innoDIApplyOverrides: @Swift.MainActor (inout Overrides) -> Void, operation _innoDIOperation: @Swift.MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let _innoDIContainer = Self(config: config, _innoDIApplyOverrides)
        return try await _innoDIOperation(_innoDIContainer)
    }
}