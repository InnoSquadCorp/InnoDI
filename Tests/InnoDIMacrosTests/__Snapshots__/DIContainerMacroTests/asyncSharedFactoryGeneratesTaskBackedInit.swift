
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var config: Config

    private var _storage_config: Config? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service

    private var _storage_task_service: Task<Service, Never>? = nil

    // MARK: - Initialization
    init(config: Config, service: Service? = nil) {
        self._storage_config = config
        let _resolved_config = self._storage_config!
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
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(config: Config, _ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(config: config, applyOverrides)
        return try await operation(container)
    }
}