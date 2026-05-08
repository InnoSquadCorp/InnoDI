
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

    // MARK: - Initialization
    @MainActor init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var apiClient: APIClient? = nil
    }

    // MARK: - Convenience Init with Overrides
    @MainActor init(userID: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, apiClient: overrides.apiClient)
    }

    // MARK: - withOverrides
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try await operation(container)
    }
}