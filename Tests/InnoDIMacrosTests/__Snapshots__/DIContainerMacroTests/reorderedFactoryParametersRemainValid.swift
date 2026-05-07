
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

    // MARK: - Initialization
    init(config: Config, logger: Logger, service: Service? = nil) {
        self._storage_config = config
        self._storage_logger = logger
        self._storage_service = service ?? { (logger: Logger, config: Config) in
                Service(config: config, logger: logger)
            }(self._storage_logger, self._storage_config)
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var service: Service? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(config: config, logger: logger, service: overrides.service)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, logger: logger, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, logger: logger, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    static func withOverrides<OperationResult>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, logger: logger, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    static func withOverrides<OperationResult>(config: Config, logger: Logger, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, logger: logger, applyOverrides)
        return try await operation(container)
    }
}