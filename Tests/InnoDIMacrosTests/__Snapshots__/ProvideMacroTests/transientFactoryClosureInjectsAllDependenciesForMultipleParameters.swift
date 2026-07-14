
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    private var _storage_apiClient: APIClient? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var logger: Logger

    private var _storage_logger: Logger? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var viewModel: ViewModel

    private var _override_viewModel: ViewModel? = nil

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
    nonisolated(nonsending) static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(apiClient: APIClient, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(apiClient: apiClient, logger: logger, applyOverrides)
        return try await operation(container)
    }
}