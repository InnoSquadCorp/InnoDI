
struct AppContainer {
    var config: Config {
        get {
            return _storage_config
        }
    }

    private let _storage_config: Config
    var logger: Logger {
        get {
            return _storage_logger
        }
    }

    private let _storage_logger: Logger
    var service: Service {
        get {
            return _storage_service
        }
    }

    private let _storage_service: Service

    init(config: Config, logger: Logger, service: Service? = nil) {
        self._storage_config = config
        self._storage_logger = logger
        self._storage_service = service ?? { (logger: Logger, config: Config) in
                Service(config: config, logger: logger)
            }(self._storage_logger, self._storage_config)
    }

    struct Overrides {
        var service: Service? = nil
    }

    init(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, logger: logger, service: overrides.service)
    }

    static func withOverrides<T>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> T) -> T {
        let container = Self(config: config, logger: logger, applyOverrides)
        return operation(container)
    }

    static func withOverrides<T>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> T) throws -> T {
        let container = Self(config: config, logger: logger, applyOverrides)
        return try operation(container)
    }

    static func withOverrides<T>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> T) async -> T {
        let container = Self(config: config, logger: logger, applyOverrides)
        return await operation(container)
    }

    static func withOverrides<T>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> T) async throws -> T {
        let container = Self(config: config, logger: logger, applyOverrides)
        return try await operation(container)
    }
}