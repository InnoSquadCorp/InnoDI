
struct AppContainer {
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var service: Service

    private var _storage_service: Service? = nil
    @InnoDI._InnoDIProvideAccessor(recovery: false)
    var laterService: LaterService

    private var _storage_laterService: LaterService? = nil

    // MARK: - Initialization
    init(service: Service? = nil, laterService: LaterService? = nil) {
        func _innoDIUnresolvedDependency<T>(_ name: String) -> T {
            fatalError("InnoDI could not resolve dependency '\(name)' while expanding a container with validateDAG: false. Supply an explicit override or complete the container wiring.")
        }
        self._storage_service = service ?? { (laterService: LaterService, missing: MissingService) in
                Service(laterService: laterService, missing: missing)
            }(laterService ?? _innoDIUnresolvedDependency("laterService"), _innoDIUnresolvedDependency("missing"))
        self._storage_laterService = laterService ?? LaterService()
    }

    // MARK: - Overrides Builder
    struct Overrides {
        var service: Service? = nil
        var laterService: LaterService? = nil
    }

    // MARK: - Convenience Init with Overrides
    init(_ applyOverrides: (inout Overrides) -> Void) {
        var overrides = Overrides()
        applyOverrides(&overrides)
        self.init(service: overrides.service, laterService: overrides.laterService)
    }

    // MARK: - withOverrides
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) -> OperationResult) -> OperationResult {
        let container = Self(applyOverrides)
        return operation(container)
    }

    // MARK: - withOverrides (throws)
    static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: (Self) throws -> OperationResult) throws -> OperationResult {
        let container = Self(applyOverrides)
        return try operation(container)
    }

    // MARK: - withOverrides (async)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async -> OperationResult) async -> OperationResult {
        let container = Self(applyOverrides)
        return await operation(container)
    }

    // MARK: - withOverrides (async throws)
    nonisolated(nonsending) static func withOverrides<OperationResult>(_ applyOverrides: (inout Overrides) -> Void, operation: nonisolated(nonsending) (Self) async throws -> OperationResult) async throws -> OperationResult {
        let container = Self(applyOverrides)
        return try await operation(container)
    }
}