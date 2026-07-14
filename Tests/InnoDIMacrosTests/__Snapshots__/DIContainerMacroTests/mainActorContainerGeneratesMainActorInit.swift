
struct AppContainer {
    @MainActor
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config

    // MARK: - Initialization
    @MainActor init(config: Config) {
        self._storage_config = config
    }

    // MARK: - Overrides Builder
    @MainActor struct Overrides {
    }

    // MARK: - Convenience Init with Overrides
    @MainActor init(config: Config, _ applyOverrides: @MainActor (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config)
    }

    // MARK: - withOverrides
    @MainActor static func withOverrides<OperationResult>(config: Config, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    @MainActor static func withOverrides<OperationResult>(config: Config, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    @MainActor static func withOverrides<OperationResult>(config: Config, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    @MainActor static func withOverrides<OperationResult>(config: Config, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}