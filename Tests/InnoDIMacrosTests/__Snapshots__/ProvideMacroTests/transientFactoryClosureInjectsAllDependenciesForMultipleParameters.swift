
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

    // MARK: - Initialization
    init(apiClient: APIClient, logger: Logger, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient
        self._storage_logger = logger
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(apiClient: apiClient, logger: logger, viewModel: overrides.viewModel)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return try await operation(container)
    }
}