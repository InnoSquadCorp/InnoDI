
struct AppContainer {
    var baseURL: String {
        get {
            return _storage_baseURL
        }
    }

    private let _storage_baseURL: String

    init(baseURL: String) {
        self._storage_baseURL = baseURL
    }

    struct Overrides {
    }

    init(baseURL: String, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(baseURL: baseURL)
    }

    static func withOverrides<T>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(baseURL: baseURL, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(baseURL: baseURL, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(baseURL: baseURL, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(baseURL: String, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(baseURL: baseURL, applyOverrides)
        return try await operation(container)
    }
}
