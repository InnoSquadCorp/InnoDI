
struct AppContainer {
    var userID: String {
        get {
            return _storage_userID
        }
    }

    private let _storage_userID: String
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
            return {
                ViewModel()
            }()
        }
    }

    private let _override_viewModel: ViewModel?

    init(userID: String, apiClient: APIClient? = nil, viewModel: ViewModel? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
        self._override_viewModel = viewModel
    }

    struct Overrides {
        var apiClient: APIClient? = nil
        var viewModel: ViewModel? = nil
    }

    init(userID: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, apiClient: overrides.apiClient, viewModel: overrides.viewModel)
    }

    static func withOverrides<T>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(userID: userID, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(userID: userID, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(userID: userID, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(userID: userID, applyOverrides)
        return try await operation(container)
    }
}