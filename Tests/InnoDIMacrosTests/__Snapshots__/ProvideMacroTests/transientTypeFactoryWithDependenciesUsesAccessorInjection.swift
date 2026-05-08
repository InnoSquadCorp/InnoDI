
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return ViewModel(config: self.config)
        }
    }

    private let _override_viewModel: ViewModel?

    // MARK: - Initialization
    init(config: Config, viewModel: ViewModel? = nil) {
        self._storage_config = config
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, viewModel: overrides.viewModel)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}