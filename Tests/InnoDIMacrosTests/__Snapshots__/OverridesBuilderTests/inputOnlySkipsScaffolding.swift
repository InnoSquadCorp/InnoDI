
struct AppContainer {
    var userID: String {
        get {
            return _storage_userID
        }
    }

    private let _storage_userID: String
    var baseURL: String {
        get {
            return _storage_baseURL
        }
    }

    private let _storage_baseURL: String

    // MARK: - Initialization
    init(userID: String, baseURL: String) {
        self._storage_userID = userID
        self._storage_baseURL = baseURL
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    // MARK: - Convenience Init with Overrides
    init(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, baseURL: baseURL)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return try await operation(container)
    }
}