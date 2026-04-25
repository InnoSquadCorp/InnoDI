
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

    init(userID: String, baseURL: String) {
        self._storage_userID = userID
        self._storage_baseURL = baseURL
    }

    struct Overrides {
    }

    init(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(userID: userID, baseURL: baseURL)
    }

    static func withOverrides<T>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(userID: String, baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(userID: userID, baseURL: baseURL, applyOverrides)
        return try await operation(container)
    }
}