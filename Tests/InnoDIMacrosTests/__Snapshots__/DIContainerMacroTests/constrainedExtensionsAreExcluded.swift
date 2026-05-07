
struct AppContainer<T> {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config

    // MARK: - Initialization
    init(config: Config) {
        self._storage_config = config
    }

    // MARK: - Overrides Builder
    struct Overrides {
    }

    // MARK: - Convenience Init with Overrides
    init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config)
    }

    // MARK: - withOverrides
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: withOverrides (throws)
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: withOverrides (async)
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: withOverrides (async throws)
    static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}

extension AppContainer where T: Sendable {
    init(config: Config, debug: Bool) {
        self.init(config: config)
    }
}