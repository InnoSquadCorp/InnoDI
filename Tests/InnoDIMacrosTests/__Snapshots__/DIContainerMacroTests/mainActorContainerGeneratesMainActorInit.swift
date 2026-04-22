
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config

    @MainActor init(config: Config) {
        self._storage_config = config
    }

    struct Overrides {
    }

    @MainActor init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    @MainActor static func withOverrides<T>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}