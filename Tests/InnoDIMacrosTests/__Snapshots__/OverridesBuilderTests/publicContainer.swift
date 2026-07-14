
public struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var userID: String
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var apiClient: APIClient

    // MARK: - Initialization
    public init(userID: String, apiClient: APIClient? = nil) {
        self._storage_userID = userID
        self._storage_apiClient = apiClient ?? APIClient()
    }

    // MARK: - Overrides Builder
    public struct Overrides {
        public var apiClient: APIClient? = nil
    }

    // MARK: - Convenience Init with Overrides
    public init(userID: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, apiClient: overrides.apiClient)
    }

    // MARK: - withOverrides
    public static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    public static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    public nonisolated(nonsending) static func withOverrides<OperationResult>(userID: String, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(userID: userID, applyOverrides)
        return try await operation(container)
    }
}