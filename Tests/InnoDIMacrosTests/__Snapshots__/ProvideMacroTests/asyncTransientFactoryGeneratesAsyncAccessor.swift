
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var viewModel: ViewModel {
        get async {
            if let override = _override_viewModel {
                return override
            }
            return await { (apiClient: APIClient) async in
                await ViewModel.load(apiClient: apiClient)
            }(self.apiClient)
        }
    }

    private let _override_viewModel: ViewModel?

    // MARK: - Initialization
    init(apiClient: APIClient, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient
        self._override_viewModel = viewModel
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(apiClient: apiClient, viewModel: overrides.viewModel)
    }

    // MARK: - withOverrides
    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return try await operation(container)
    }
}