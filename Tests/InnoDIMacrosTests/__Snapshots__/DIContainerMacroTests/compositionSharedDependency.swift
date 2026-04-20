
struct AppContainer {
    var apiClient: APIClientProtocol & LoggerProtocol {
        get {
            return _storage_apiClient
        }
    }

    private let _storage_apiClient: APIClientProtocol & LoggerProtocol

    init(apiClient: (APIClientProtocol & LoggerProtocol)? = nil) {
        self._storage_apiClient = apiClient ?? APIClient()
    }

    struct Overrides {
        var apiClient: (APIClientProtocol & LoggerProtocol)? = nil
    }

    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(apiClient: overrides.apiClient)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}