
struct AppContainer {
    var apiClient: APIClientProtocol & LoggerProtocol {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClientProtocol & LoggerProtocol

    // MARK: - Initialization
    init(apiClient: (APIClientProtocol & LoggerProtocol)? = nil) {
        self._storage_apiClient = apiClient ?? APIClient()
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var apiClient: (APIClientProtocol & LoggerProtocol)? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(apiClient: overrides.apiClient)
    }

    // MARK: - withOverrides
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}