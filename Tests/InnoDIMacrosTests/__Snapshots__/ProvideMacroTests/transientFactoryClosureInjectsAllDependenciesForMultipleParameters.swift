
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var logger: Logger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: Logger
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return { (apiClient: APIClient, logger: Logger) in
                ViewModel(apiClient: apiClient, logger: logger)
            }(self.apiClient, self.logger)
        }
    }

    private let _override_viewModel: ViewModel?

    init(apiClient: APIClient, logger: Logger, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient
        self._storage_logger = logger
        self._override_viewModel = viewModel
    }

    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    init(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(apiClient: apiClient, logger: logger, viewModel: overrides.viewModel)
    }

    static func withOverrides<T>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return try await operation(container)
    }
}