
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var service: Service {
        get async {
            return await _storage_task_service.value
        }
    }

    private let _storage_task_service: Task<Service, Never>

    // MARK: - Initialization
    init(config: Config, service: Service? = nil) {
        self._storage_config = config
        let _resolved_config = config
        let _task_service = Task<Service, Never> {
            if let override = service {
                return override
            }
            return await { (config: Config) async in
                Service(config: config)
            }(_resolved_config)
        }
        self._storage_task_service = _task_service
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var service: Service? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(config: Config, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, service: overrides.service)
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