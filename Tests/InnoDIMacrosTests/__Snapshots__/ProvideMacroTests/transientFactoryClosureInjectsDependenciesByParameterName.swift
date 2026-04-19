
struct AppContainer {
    var apiClient: APIClient {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClient
    var viewModel: ViewModel {
        get {
            if let override = _override_viewModel {
                return override
            }
            return { (apiClient: APIClient) in
                ViewModel(apiClient: apiClient)
            }(self.apiClient)
        }
    }

    private let _override_viewModel: ViewModel?

    init(apiClient: APIClient, viewModel: ViewModel? = nil) {
        self._storage_apiClient = apiClient
        self._override_viewModel = viewModel
    }

    struct Overrides {
        var viewModel: ViewModel? = nil
    }

    init(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(apiClient: apiClient, viewModel: overrides.viewModel)
    }

    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(apiClient: APIClient, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(apiClient: apiClient, applyOverrides)
        return try await operation(container)
    }
}