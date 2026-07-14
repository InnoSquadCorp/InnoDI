
struct AppContainer {
    @MainActor
    var userID: String {
        get {
            return _storage_userID
        }
    }

    private let _storage_userID: String
    @MainActor
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
    @MainActor struct Overrides {
        var apiClient: APIClient? = nil
    }

    // MARK: - Convenience Init with Overrides
    @MainActor init(userID: String, _ applyOverrides: @MainActor (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, apiClient: overrides.apiClient)
    }

    // MARK: - withOverrides
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) -> OperationResult) -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    @MainActor static func withOverrides<OperationResult>(userID: String, _ applyOverrides: @MainActor (inout Overrides) -> Void, operation: @MainActor (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try await operation(container)
    }
}