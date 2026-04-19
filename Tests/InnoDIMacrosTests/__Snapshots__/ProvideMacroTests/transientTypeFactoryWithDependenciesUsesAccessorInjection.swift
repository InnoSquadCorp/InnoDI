
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

    init(config: Config, viewModel: ViewModel? = nil) {
        self._storage_config = config
        self._override_viewModel = viewModel
    }

    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, viewModel: overrides.viewModel)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}